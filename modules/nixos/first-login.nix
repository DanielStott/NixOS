# Stage 2 bootstrap: at the first login a terminal runs `nixos-finish-setup` once. It
# signs in with the owner's own GitHub App (device flow: approve a code on the phone; the
# App is installed on the private repo only), uses that short-lived token, in memory only,
# to add a read-only deploy key, clones the private flake to /etc/nixos-private
# (root-owned, so no env can edit the config), installs the age key if the private repo
# has sops secrets, and switches to the private flake.
# `nixos-update` pulls the private repo and rebuilds from it afterwards.
{ config, lib, pkgs, ... }:
let
  cfg = config.firstLogin;
  host = config.networking.hostName;
  dest = "/etc/nixos-private";
  keyFile = "/root/.ssh/nixos-private";
  gitSsh = "ssh -i ${keyFile} -o IdentitiesOnly=yes";

  finishSetup = pkgs.writeShellApplication {
    name = "nixos-finish-setup";
    runtimeInputs = with pkgs; [ git openssh coreutils gnugrep curl jq qrencode ];
    text = ''
      repo="${cfg.privateRepo}"
      client_id="${cfg.githubAppClientId}"
      state="$HOME/.local/state/nixos-setup"
      mkdir -p "$state"
      say() { printf '\n== %s\n' "$*"; }
      pause() { read -r -p "$1 Press Enter to continue. " _; }

      say "Finishing setup: private config from $repo"
      echo "Some steps write to /etc and /root, so sudo asks for your login password once."

      until curl -fsS --max-time 5 https://github.com >/dev/null 2>&1; do
        pause "No internet yet. Connect with Super+S (control centre) or a cable."
      done

      if ! sudo test -e ${dest}/.git; then
        say "1. Approve this laptop on your phone"
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

        say "3. Cloning the private config to ${dest}"
        sudo env GIT_SSH_COMMAND="${gitSsh}" git clone "git@github.com:$repo.git" ${dest}
        sudo git -C ${dest} config core.sshCommand "${gitSsh}"
        sudo chmod 700 ${dest} # private notes and (encrypted) secrets: root only
      fi

      if sudo test -e ${dest}/.sops.yaml && ! sudo test -e /var/lib/sops-nix/key.txt; then
        say "4. Paste the age recovery key from your password manager (input is hidden)"
        read -r -s -p "age key: " agekey; echo
        sudo install -d -m 700 /var/lib/sops-nix
        printf '%s\n' "$agekey" | sudo tee /var/lib/sops-nix/key.txt >/dev/null
        sudo chmod 600 /var/lib/sops-nix/key.txt
        unset agekey
      fi

      if ! sudo test -e ${dest}/flake.nix; then
        say "The private repo has no flake yet, so this machine stays on the base config."
        echo "Access is set up; run nixos-finish-setup again once the private flake exists."
        pause "Done for now."
        exit 0
      fi

      say "5. Switching to the private config (this downloads and builds for a while)"
      sudo nixos-rebuild switch --flake "${dest}#${host}"
      touch "$state/done"
      say "All set. The envs are ready."
      pause ""
    '';
  };

  update = pkgs.writeShellApplication {
    name = "nixos-update";
    runtimeInputs = with pkgs; [ git ];
    text = ''
      sudo git -C ${dest} pull --ff-only
      sudo nixos-rebuild switch --flake "${dest}#${host}"
    '';
  };
in
{
  options.firstLogin = {
    privateRepo = lib.mkOption {
      type = lib.types.str;
      example = "owner/nixos-private";
      description = "GitHub repo (owner/name) of the private flake layered on this base.";
    };
    githubAppClientId = lib.mkOption {
      type = lib.types.str;
      description = ''
        Client ID (not a secret) of the owner's GitHub App used for the first-login device
        flow. The App needs the Administration permission, device flow enabled, and should
        be installed on the private repo only.
      '';
    };
  };

  config = {
    environment.systemPackages = [ finishSetup update ];

    # GitHub's published SSH host key, so the first clone can't be intercepted.
    programs.ssh.knownHosts."github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };
}
