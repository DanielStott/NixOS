# Dell Precision 7680: i7-13850HX, Intel Raptor Lake iGPU + NVIDIA RTX 2000 Ada (laptop).
# NixOS lives on the second NVMe (Samsung 980), next to Pop!_OS on the first. The
# partitions are found by GPT partition label, so nothing here names a disk serial:
#   NIXOS-ESP    1 GiB   vfat, mounted at /boot
#   NIXOS-CRYPT  rest    LUKS2 (passphrase at boot) holding Btrfs subvolumes
# Compare with `nixos-generate-config --show-hardware-config` from the installer.
{ config, lib, modulesPath, ... }:
let
  btrfs = subvol: {
    device = "/dev/mapper/cryptnixos";
    fsType = "btrfs";
    options = [ "subvol=${subvol}" "compress=zstd" "noatime" ];
  };
in
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci" "thunderbolt" "vmd" "nvme" "usb_storage" "uas" "sd_mod" "rtsx_pci_sdmmc"
    # QEMU disks, so the same install can be rehearsed in a VM first
    "virtio_pci" "virtio_blk" "virtio_scsi"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = true;

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

  swapDevices = [ ];
  zramSwap.enable = true;

  # PCI addresses for PRIME offload (lspci: 00:02.0 Intel, 01:00.0 NVIDIA). Only used
  # when modules/nixos/nvidia-prime.nix is imported instead of nvidia-off.nix.
  hardware.nvidia.prime = {
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
