# Everything every machine gets: boot, Nix itself, locale, networking, sound, shell.
{ pkgs, ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
    editor = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Latest stable kernel: every env shares it, so security fixes should land quickly.
  # (This is why the NVIDIA driver is off for now: 595.71.05 doesn't build against 7.x.)
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.initrd.systemd.enable = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # Only root may change Nix's trust settings; env users never join trusted-users.
    trusted-users = [ "root" ];
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = true;

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "uk";
  services.xserver.xkb.layout = "gb";

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  hardware.bluetooth.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  services.fwupd.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Lid: suspend on battery; with power or an external screen attached, Hyprland
  # just turns the laptop panel off instead.
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  security.sudo.extraConfig = "Defaults lecture = never";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    git
    gh
    curl
    wget
    htop
    pciutils
    usbutils
    file
    unzip
    ripgrep
    fd
    jq
    btrfs-progs
    cryptsetup
  ];

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.jetbrains-mono
  ];
}
