# The host user's desktop: Hyprland's config, Noctalia, lock and idle, shell, terminal.
{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  home.username = "stott";
  home.homeDirectory = "/home/stott";
  home.stateVersion = "26.05";

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    # Hyprland itself comes from programs.hyprland in the system config.
    package = null;
    portalPackage = null;
    extraConfig = builtins.readFile ./hyprland.lua;
  };

  programs.noctalia = {
    enable = true;
    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
      shell = {
        # Settings are declared here, so skip the first-run wizard. Left on, its panel
        # took the keyboard from the lock screen at first login (seen in the VM test).
        setup_wizard_enabled = false;
        telemetry_enabled = false;
      };
    };
  };

  programs.hyprlock = {
    enable = true;
    # A solid background (a screenshot is just black at boot), a clock, and a password
    # box that is always visible, so the lock screen is unmistakable.
    settings = {
      general.hide_cursor = true;
      background = [{ color = "rgb(1e1e2e)"; }];
      label = [
        {
          text = "$TIME";
          font_size = 96;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(cdd6f4)";
          position = "0, 160";
          halign = "center";
          valign = "center";
        }
        {
          text = "cmd[update:60000] date +'%A %-d %B'";
          font_size = 22;
          color = "rgb(a6adc8)";
          position = "0, 60";
          halign = "center";
          valign = "center";
        }
      ];
      input-field = [{
        size = "320, 56";
        position = "0, -60";
        halign = "center";
        valign = "center";
        fade_on_empty = false;
        placeholder_text = "Password";
        outer_color = "rgb(89b4fa)";
        inner_color = "rgb(313244)";
        font_color = "rgb(cdd6f4)";
      }];
    };
  };

  # Idle: lock at 5 min, screens off at 10, suspend at 30 but only on battery.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
      };
      listener = [
        { timeout = 300; on-timeout = "loginctl lock-session"; }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
          on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
        }
        {
          timeout = 1800;
          # Only suspend on battery (AC/online is 0); plugged in, the laptop stays up.
          condition_cmd = "grep -q 0 /sys/class/power_supply/AC/online";
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" ];
    };
  };

  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 12;
      theme = "Catppuccin Mocha";
    };
  };

  # The host only pulls its config; commits happen inside envs, which set their own
  # git identity in the private layer.
  programs.git.enable = true;

  gtk = {
    enable = true;
    colorScheme = "dark";
  };
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
