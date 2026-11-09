# First login, on the console: `nixos-finish-setup` runs once. It signs in with your own
# GitHub App (device flow: approve a code on your phone; the App should be installed on the
# private repo only), uses that short-lived token, in memory only, to add a read-only
# deploy key, clones your private flake to /etc/nixos-private (root only), installs its
# nixosConfigurations.<hostName> as the next boot, and restarts into it.
{ lib, pkgs, machine, ... }:
let
  dest = "/etc/nixos-private";
  keyFile = "/root/.ssh/nixos-private";
  gitSsh = "ssh -i ${keyFile} -o IdentitiesOnly=yes";
  host = machine.hostName;

  finishSetup = pkgs.writeShellApplication {
    name = "nixos-finish-setup";
    runtimeInputs = with pkgs; [ git openssh coreutils gnugrep curl jq qrencode networkmanager ];
    text = ''
      repo=${lib.escapeShellArg machine.privateRepo}
      client_id=${lib.escapeShellArg machine.githubAppClientId}
      state="$HOME/.local/state/nixos-setup"
      mkdir -p "$state"
      say() { printf '\n== %s\n' "$*"; }
      pause() { read -r -p "$1 Press Enter to continue. " _; }

      say "Finishing setup: your private config from $repo"
      echo "Some steps write to /etc and /root, so sudo asks for your password once."

      until curl -fsS --max-time 5 https://github.com >/dev/null 2>&1; do
        pause "No internet yet. Plug in a cable, or pick a Wi-Fi network next."
        nmtui-connect || true
      done

      if ! sudo test -e ${dest}/.git; then
        say "1. Approve this machine on your phone"
        resp="$(curl -fsS -X POST -H 'Accept: application/json' \
          -d "client_id=$client_id" https://github.com/login/device/code)"
        device_code="$(jq -r .device_code <<<"$resp")"
        user_code="$(jq -r .user_code <<<"$resp")"
        uri="$(jq -r .verification_uri <<<"$resp")"
        interval="$(jq -r '.interval // 5' <<<"$resp")"
        deadline=$(( $(date +%s) + $(jq -r '.expires_in // 900' <<<"$resp") ))
        echo "Open $uri (scan below) and enter the code:   $user_code"
        qrencode -t ansiutf8 "$uri"

        token=""
        while [ -z "$token" ]; do
          sleep "$interval"
          [ "$(date +%s)" -lt "$deadline" ] || { echo "The code expired. Run nixos-finish-setup again."; exit 1; }
          r="$(curl -sS -X POST -H 'Accept: application/json' \
            -d "client_id=$client_id" -d "device_code=$device_code" \
            -d 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
            https://github.com/login/oauth/access_token)"
          case "$(jq -r '.error // empty' <<<"$r")" in
            "") token="$(jq -r .access_token <<<"$r")" ;;
            authorization_pending) ;;
            slow_down) interval=$(( interval + 5 )) ;;
            access_denied) echo "Not approved. Run nixos-finish-setup again."; exit 1 ;;
            *) echo "GitHub said: $(jq -r '.error_description // .error' <<<"$r")"; exit 1 ;;
          esac
        done

        say "2. Adding a read-only key for $repo"
        sudo install -d -m 700 /root/.ssh
        sudo test -e ${keyFile} || sudo ssh-keygen -q -t ed25519 -N "" -C "${host} read-only" -f ${keyFile}
        body="$(jq -n --arg t "${host} (read-only)" --arg k "$(sudo cat ${keyFile}.pub)" \
          '{title: $t, key: $k, read_only: true}')"
        # The token goes to curl through a config on a pipe, not on the command line.
        code="$(curl -sS -o "$state/deploy-key-reply.json" -w '%{http_code}' -X POST \
          --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
          -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' \
          --data "$body" "https://api.github.com/repos/$repo/keys")"
        unset token
        if [ "$code" != "201" ] && ! grep -q 'already in use' "$state/deploy-key-reply.json"; then
          echo "GitHub refused the key (HTTP $code):"; cat "$state/deploy-key-reply.json"; exit 1
        fi

        say "3. Cloning your private config to ${dest}"
        sudo env GIT_SSH_COMMAND="${gitSsh}" git clone "git@github.com:$repo.git" ${dest}
        sudo git -C ${dest} config core.sshCommand "${gitSsh}"
        sudo chmod 700 ${dest}
      fi

      if ! sudo test -e ${dest}/flake.nix; then
        say "The private repo has no flake.nix, so this machine stays as it is."
        echo "Run nixos-finish-setup again once it has one."
        exit 0
      fi

      say "4. Installing your config (${host}) for the next start; this downloads a lot"
      # Your flake's own settings (extra binary caches) are accepted: it's your config.
      sudo nixos-rebuild boot --flake "${dest}#${host}" --option accept-flake-config true
      touch "$state/done"
      say "Done. Restarting into your system."
      pause ""
      sudo systemctl reboot
    '';
  };
in
{
  environment.systemPackages = [ finishSetup ];

  # Starts by itself at the first console login on tty1 (until it has finished once).
  programs.bash.loginShellInit = ''
    if [ "$(id -un)" = ${lib.escapeShellArg machine.user} ] && [ "$(tty)" = /dev/tty1 ] \
      && [ ! -e "$HOME/.local/state/nixos-setup/done" ]; then
      nixos-finish-setup
    fi
  '';

  # GitHub's published SSH host key, so the first clone can't be intercepted.
  programs.ssh.knownHosts."github.com".publicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
}
