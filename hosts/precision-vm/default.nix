# A VM copy of `precision` for trying the desktop before installing: the same modules,
# but no laptop disk layout (the image builder makes its own disk) and no NVIDIA handling.
# Test-only password: nixos. Build: .#nixosConfigurations.precision-vm.config.system.build.images.iso
# Run: tools/run-vm.sh <scratch.qcow2> <the .iso>  (the disk is just a place to save files)
{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/nixos/base.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/snapshots.nix
    ../../modules/nixos/first-login.nix
  ];

  networking.hostName = "precision-vm";
  firstLogin.privateRepo = "DanielStott/nixos-private";
  firstLogin.githubAppClientId = "Iv23li7v3RCkVRA94bGq"; # DanielStott-nixos-setup (not a secret)

  users.users.stott = {
    isNormalUser = true;
    description = "Daniel Stott";
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    initialPassword = "nixos"; # VM only
  };

  # Diagnostics for the test VM only: boot messages on the serial port (run-vm.sh writes
  # them to a file) and SSH (forwarded to the host's port 2222) with a VM-only key.
  boot.kernelParams = [ "console=tty1" "console=ttyS0,115200" ];
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
  users.users.stott.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEBaRvtYb+BnQZMcaRF3hRNmlEc18Xodrot+DNzUw9d1 precision-vm test only"
  ];

  # The image is built without access to EFI variables; the VM's firmware finds the ESP.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  hardware.graphics.enable = true;
  services.snapper.configs = lib.mkForce { }; # the image's root isn't Btrfs

  # Built as a live ISO (squashfs), which the VM boots straight into the desktop.
  # The qcow2 disk-image builder ran out of memory copying a desktop-sized system.
  image.modules.iso = {
    boot.loader.systemd-boot.enable = lib.mkForce false; # the ISO brings its own loader
    isoImage.makeEfiBootable = true; # off by default; the VM (like the laptop) boots UEFI
    isoImage.makeUsbBootable = true;
    isoImage.squashfsCompression = "zstd -Xcompression-level 6";
  };

  system.stateVersion = "26.05";
}
