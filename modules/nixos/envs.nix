# Qubes-lite environments: each `envs.<name>` becomes a NixOS container (systemd-nspawn)
# with its own UID range, its own network (internet only unless `lan = true`), an empty
# root at every start (`ephemeral`) and a persistent home.
#
# Its windows reach the host's Hyprland directly (full GPU, dmabuf) through a socket made
# with wp_security_context_v1 (pkgs/env-wayland-socket), so Hyprland withholds privileged
# protocols from it: no screen capture, clipboard managers, virtual keyboards or window
# management. Hyprland tags each window with its env from the kernel's cgroup of the
# client process (which an app can't fake) and gives it the env's border colour.
# X11 apps get their own Xwayland inside the env (xwayland-satellite).
#
#   envs.work = { id = 1; label = "Work"; color = "rgb(89b4fa)"; packages = [ ... ]; };
#
# Launch from the host with `env-run <env> [command]` (a terminal if no command), or from
# the launcher, where each app appears once per env as "App · Label".
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkOption types mkIf mapAttrs mapAttrs' mapAttrsToList nameValuePair
    optional optionalAttrs concatStringsSep concatMapStringsSep filterAttrs;

  cfg = config.envs;
  enabled = filterAttrs (_: e: e.enable) cfg;
  user = config.envHostUser;
  hostGraphicsExtras = config.hardware.graphics.extraPackages; # e.g. the iGPU's video decode driver
  uidBase = e: 268435456 + e.id * 65536; # 0x10000000 + id * 0x10000: each env's own range
  runDir = name: "/run/envs/${name}";
  stateDir = name: "/var/lib/envs/${name}";
  lanRanges = "10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10";

  envOptions = { name, ... }: {
    options = {
      enable = mkOption { type = types.bool; default = true; };
      id = mkOption {
        type = types.ints.between 1 250;
        description = "Small unique number: picks the env's UID range and its 10.231.<id>.0/24 link.";
      };
      label = mkOption { type = types.str; default = name; description = "Shown as [label] in window titles."; };
      color = mkOption { type = types.str; default = "rgb(89b4fa)"; description = "Hyprland border colour for this env's windows."; };
      packages = mkOption { type = types.listOf types.package; default = [ ]; };
      gpu = mkOption { type = types.bool; default = true; description = "Give the env the GPU's render node."; };
      lan = mkOption { type = types.bool; default = false; description = "Allow the home LAN (otherwise internet only)."; };
      audio = mkOption {
        type = types.bool;
        default = true;
        description = "Sound and microphone through a restricted PipeWire-Pulse socket (can't control other apps' streams).";
      };
      nixDaemon = mkOption { type = types.bool; default = false; description = "Let the env talk to the host's Nix daemon (for nix develop)."; };
      binds = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = { "Code" = "/mnt/data/Code/Personal"; };
        description = "Host folders mounted read-write under the env user's home (name -> host path).";
      };
      extraConfig = mkOption {
        type = types.deferredModule;
        default = { };
        description = "Extra NixOS configuration inside the env.";
      };
    };
  };

  # Host-side launcher: start the env if needed, then run the command as the env's user.
  envLaunch = pkgs.writeShellApplication {
    name = "env-launch";
    runtimeInputs = [ config.systemd.package pkgs.coreutils ];
    text = ''
      known=" ${concatStringsSep " " (builtins.attrNames enabled)} "
      env="''${1:-}"
      [ -n "$env" ] && [[ "$known" == *" $env "* ]] || { echo "usage: env-launch <env> [command...]  (envs:$known)" >&2; exit 2; }
      shift
      [ "$#" -gt 0 ] || set -- ghostty
      systemctl is-active --quiet "container@$env" || systemctl start "container@$env"
      for _ in $(seq 1 100); do
        systemd-run --machine="${user}@$env" --user --quiet --wait --collect -- /run/current-system/sw/bin/true 2>/dev/null && break
        sleep 0.2
      done
      # Through the env's login shell: the user manager doesn't search PATH for bare names.
      exec systemd-run --machine="${user}@$env" --user --quiet --collect -- \
        /run/current-system/sw/bin/bash -lc 'exec "$@"' env-run "$@"
    '';
  };

  envRun = pkgs.writeShellApplication {
    name = "env-run";
    text = ''exec sudo -n /run/current-system/sw/bin/env-launch "$@"'';
  };

  # "App · Label" launcher entries for every .desktop file in an env's packages, plus a
  # terminal; icons are linked in so the launcher can show them. No binaries reach the host.
  launchers = pkgs.runCommand "env-launchers" { } ''
    mkdir -p $out/share/applications $out/share/icons $out/share/pixmaps
    ${concatStringsSep "\n" (mapAttrsToList (name: e: ''
      cat > $out/share/applications/env-${name}-terminal.desktop <<EOF
      [Desktop Entry]
      Type=Application
      Name=Terminal · ${e.label}
      Exec=env-run ${name}
      Icon=com.mitchellh.ghostty
      Categories=System;TerminalEmulator;
      EOF
      for p in ${concatStringsSep " " e.packages}; do
        for f in "$p"/share/applications/*.desktop; do
          [ -e "$f" ] || continue
          sed -e 's|^Exec=|Exec=env-run ${name} |' \
              -e '/^Name\(\[[^]]*\]\)\?=/ s|$| · ${e.label}|' \
              -e '/^TryExec=/d' -e '/^DBusActivatable=/d' \
              "$f" > "$out/share/applications/env-${name}-$(basename "$f")"
        done
        [ -d "$p/share/icons" ] && cp -rsn "$p/share/icons/." $out/share/icons/ 2>/dev/null || true
        [ -d "$p/share/pixmaps" ] && cp -rsn "$p/share/pixmaps/." $out/share/pixmaps/ 2>/dev/null || true
      done
    '') enabled)}
  '';

  envWaylandSocket = pkgs.callPackage ../../pkgs/env-wayland-socket { };

  # Tag each new window with its env (from the client's cgroup: container@<env>.service) and
  # give it the env's border colour, focused or not. Set per window once rules have run.
  envHyprland = ''
    local env_colors = { ${concatStringsSep ", " (mapAttrsToList (name: e: ''["${name}"] = "${e.color}"'') enabled)} }
    hl.on("window.open", function(w)
      if not w.pid or w.pid <= 0 then return end
      local f = io.open("/proc/" .. w.pid .. "/cgroup", "r")
      if not f then return end
      local cgroup = f:read("*a")
      f:close()
      local env = cgroup:match("container@([%w_-]+)%.service")
      if not env then return end
      local sel = "address:" .. w.address
      hl.dispatch(hl.dsp.window.tag({ tag = "+env-" .. env, window = sel }))
      local color = env_colors[env]
      if color then
        hl.dispatch(hl.dsp.window.set_prop({ prop = "active_border_color", value = color, window = sel }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "inactive_border_color", value = color, window = sel }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "border_size", value = "3", window = sel }))
      end
    end)
  '';
in
{
  options = {
    envs = mkOption {
      type = types.attrsOf (types.submodule envOptions);
      default = { };
      description = "Isolated environments (see the comment at the top of envs.nix).";
    };
    envHostUser = mkOption {
      type = types.str;
      default = "stott";
      description = "Host user who runs the env proxies and launches apps; the same name is used inside each env.";
    };
  };

  config = mkIf (enabled != { }) {
    assertions = [{
      assertion = builtins.length (lib.unique (mapAttrsToList (_: e: e.id) enabled)) == builtins.length (builtins.attrNames enabled);
      message = "envs: every env needs a different id";
    }];

    containers = mapAttrs (name: e: {
      autoStart = false; # started on demand by env-run
      ephemeral = true; # empty root at every start; only the home and binds persist
      restartIfChanged = false; # a rebuild must not kill running apps
      privateUsers = uidBase e;
      privateNetwork = true;
      hostAddress = "10.231.${toString e.id}.1";
      localAddress = "10.231.${toString e.id}.2";
      # `:idmap` makes files owned by the host user appear as the env user's own.
      bindMounts = {
        "home" = { hostPath = "${stateDir name}/home"; mountPoint = "/home/${user}:idmap"; isReadOnly = false; };
        "session" = { hostPath = runDir name; mountPoint = "/run/host-session:idmap"; isReadOnly = false; };
      }
      // optionalAttrs e.gpu { "dri" = { hostPath = "/dev/dri"; mountPoint = "/dev/dri"; isReadOnly = false; }; }
      // mapAttrs' (sub: src: nameValuePair "bind-${sub}" {
        hostPath = src;
        mountPoint = "/home/${user}/${sub}:idmap";
        isReadOnly = false;
      }) e.binds;
      allowedDevices = optional e.gpu { node = "char-drm"; modifier = "rw"; };
      # With a fixed UID base (unlike "pick") nspawn leaves the root's ownership alone unless
      # told; `auto` maps it (idmapped mount) so the env's root can write its own /etc.
      extraFlags = [ "--private-users-ownership=auto" "--no-new-privileges=yes" ]
        ++ optional (!e.nixDaemon) "--inaccessible=/nix/var/nix/daemon-socket";

      config = { lib, pkgs, ... }: {
        imports = [ e.extraConfig ];
        system.stateVersion = "26.05";
        nixpkgs.config.allowUnfree = true;

        networking.useHostResolvConf = lib.mkForce false;
        networking.nameservers = [ "1.1.1.1" "9.9.9.9" ];

        time.timeZone = "Europe/London";
        i18n.defaultLocale = "en_GB.UTF-8";

        users.users.${user} = {
          isNormalUser = true;
          uid = 1000;
          linger = true; # the user's systemd manager runs, so env-run can start apps in it
          shell = pkgs.zsh;
        };
        programs.zsh.enable = true;
        programs.nix-ld.enable = true;
        hardware.graphics = { enable = e.gpu; extraPackages = hostGraphicsExtras; };
        fonts.packages = with pkgs; [ noto-fonts noto-fonts-color-emoji nerd-fonts.jetbrains-mono ];
        environment.systemPackages = e.packages ++ (with pkgs; [ ghostty xwayland-satellite git adwaita-icon-theme ]);

        systemd.user.extraConfig = ''
          DefaultEnvironment="WAYLAND_DISPLAY=/run/host-session/wayland-0" "DISPLAY=:0"${lib.optionalString e.audio " \"PULSE_SERVER=unix:/run/host-session/pulse\""} "XDG_SESSION_TYPE=wayland" "NIXOS_OZONE_WL=1" "GTK_THEME=Adwaita:dark"
        '';
        # This env's own Xwayland, so X11 apps can't see other envs' windows.
        systemd.user.services.xwayland-satellite = {
          wantedBy = [ "default.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.xwayland-satellite}/bin/xwayland-satellite :0";
            Restart = "always";
            RestartSec = 2;
          };
        };
      };
    }) enabled;

    # Persistent homes (owned by the host user; idmapped into each env) and proxy sockets.
    systemd.tmpfiles.rules = lib.concatLists (mapAttrsToList (name: _: [
      "d ${stateDir name} 0700 root root -"
      "d ${stateDir name}/home 0700 ${user} users -"
      "d ${runDir name} 0700 ${user} users -"
    ]) enabled);

    # One sandboxed Wayland socket per env, made by the host user inside the desktop session.
    systemd.user.services = mapAttrs' (name: e: nameValuePair "env-wayland-${name}" {
      description = "Sandboxed Wayland socket for the ${e.label} env";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${envWaylandSocket}/bin/env-wayland-socket ${runDir name}/wayland-0 ${name}";
        Restart = "on-failure";
        RestartSec = 2;
      };
    }) enabled // {
      # pipewire-pulse is socket-activated by the host's own socket; start it with the session
      # so the env sockets exist before any env app wants sound.
      pipewire-pulse.wantedBy = mkIf (filterAttrs (_: e: e.audio) enabled != { }) [ "graphical-session.target" ];
    };

    # One restricted PipeWire-Pulse socket per env that has audio, next to its Wayland socket.
    services.pipewire.extraConfig.pipewire-pulse."60-envs" = {
      "pulse.properties"."server.address" = [ "unix:native" ]
        ++ mapAttrsToList (name: _: { address = "unix:${runDir name}/pulse"; "client.access" = "restricted"; })
          (filterAttrs (_: e: e.audio) enabled);
    };

    # Internet for every env; the LAN, other envs and the host only where allowed.
    networking.nftables.enable = true;
    networking.nat = {
      enable = true;
      internalInterfaces = [ "ve-*" ]; # nftables wildcard ("ve-+" is iptables syntax and matches nothing here)
    };
    networking.nftables.tables.envs = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter - 1; policy accept;
          iifname "ve-*" ct state established,related accept
          iifname "ve-*" drop comment "envs can't reach services on the host"
        }
        chain forward {
          type filter hook forward priority filter; policy accept;
          iifname "ve-*" ip daddr 10.231.0.0/16 drop comment "no env reaches another env"
          ${concatMapStringsSep "\n          " (name: ''iifname "ve-${name}" ip daddr { ${lanRanges} } drop comment "${name}: internet only"'')
            (builtins.attrNames (filterAttrs (_: e: !e.lan) enabled))}
          ${concatMapStringsSep "\n          " (name: ''iifname "ve-${name}" ip6 daddr { fc00::/7, fe80::/10 } drop'')
            (builtins.attrNames (filterAttrs (_: e: !e.lan) enabled))}
        }
      '';
    };

    environment.systemPackages = [ envLaunch envRun launchers ];
    security.sudo.extraRules = [{
      users = [ user ];
      commands = [{ command = "/run/current-system/sw/bin/env-launch"; options = [ "NOPASSWD" ]; }];
    }];

    home-manager.users.${user}.wayland.windowManager.hyprland.extraConfig = lib.mkAfter ''

      ------------------------------------------------------------------ envs
      ${envHyprland}
    '';
  };
}
