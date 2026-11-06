# No NVIDIA driver: the Intel iGPU drives everything (all of this laptop's display outputs
# hang off it) and the RTX is taken off the PCI bus at boot so the firmware powers it down.
# Without a driver it would otherwise sit powered on and drain the battery.
# Swap this for nvidia-prime.nix once NVIDIA ships a driver that builds against the
# kernel in use.
{ pkgs, ... }:
{
  boot.blacklistedKernelModules = [ "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];
  services.xserver.videoDrivers = [ "modesetting" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ]; # video decode/encode on the iGPU
  };

  # Remove the NVIDIA functions (USB-C controller, UCSI, audio, GPU) from the PCI bus.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
  '';
}
