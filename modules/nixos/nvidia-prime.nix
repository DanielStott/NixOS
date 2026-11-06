# NVIDIA RTX (Ada) as an offload GPU: the Intel iGPU drives the desktop, the RTX sleeps
# until an app asks for it with `nvidia-offload <app>`. Only offload works on Wayland.
# The PCI bus IDs are set per host (see hosts/*/hardware.nix).
{ config, ... }:
{
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  hardware.nvidia = {
    open = true; # Ada cards use NVIDIA's open kernel modules
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    prime.offload = {
      enable = true;
      enableOffloadCmd = true;
    };
  };
}
