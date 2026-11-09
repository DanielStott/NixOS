# The installed system until the first login hands over to your private flake: it boots
# the encrypted disk install.sh made, gets online and has your user. Nothing more.
{ lib, pkgs, machine, ... }:
let
  btrfs = subvol: {
    device = "/dev/mapper/cryptnixos";
    fsType = "btrfs";
    options = [ "subvol=${subvol}" "compress=zstd" "noatime" ];
  };
in
{
  boot.loader.systemd-boot = {
    enable = true;
    editor = false;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  # systemd in the initrd also applies console.keyMap to the passphrase prompt.
  boot.initrd.systemd.enable = true;
  hardware.enableRedistributableFirmware = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # The layout install.sh made, found by GPT partition label.
  boot.initrd.luks.devices.cryptnixos = {
    device = "/dev/disk/by-partlabel/NIXOS-CRYPT";
    allowDiscards = true;
    bypassWorkqueues = true;
  };
  fileSystems."/" = btrfs "@root";
  fileSystems."/home" = btrfs "@home";
  fileSystems."/nix" = btrfs "@nix";
  fileSystems."/var/log" = btrfs "@log" // { neededForBoot = true; };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/NIXOS-ESP";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };
  zramSwap.enable = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" ];
  };

  networking.hostName = machine.hostName;
  networking.networkmanager.enable = true; # Wi-Fi: nmtui
  networking.firewall.enable = true;
  time.timeZone = machine.timeZone;
  console.keyMap = machine.keyMap;

  # The password is set during install (passwd); nothing secret lives here.
  users.users.${machine.user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  environment.systemPackages = with pkgs; [ git curl ];

  # The NixOS release this machine was first installed with; keep it in your private flake.
  system.stateVersion = "26.05";
}
