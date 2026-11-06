# Hyprland with the Noctalia shell. After the disk passphrase the session starts
# straight away and locks itself (hyprlock), so the passphrase is the only boot prompt
# and the user password unlocks the screen.
{ pkgs, ... }:
{
  programs.hyprland.enable = true;
  programs.hyprlock.enable = true; # PAM service for the lock screen; settings live in Home Manager

  services.greetd = {
    enable = true;
    settings = {
      # First login after boot: straight into Hyprland (the config locks at start).
      # start-hyprland is Hyprland's own watchdog launcher (recommended since 0.53).
      initial_session = {
        command = "start-hyprland";
        user = "stott";
      };
      # After logging out: a text login screen.
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd start-hyprland";
        user = "greeter";
      };
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = false;
  services.gvfs.enable = true; # trash and network places in Nautilus

  environment.systemPackages = with pkgs; [
    ghostty
    nautilus
    hyprpolkitagent
    grim
    slurp
    wl-clipboard
    brightnessctl
    playerctl
    libnotify
    adwaita-icon-theme
  ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
