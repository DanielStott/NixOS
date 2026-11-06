{ ... }:
{
  imports = [
    ./hardware.nix
    ../../modules/nixos/base.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/nvidia-off.nix # iGPU only; nvidia-prime.nix once a driver builds for the kernel
    ../../modules/nixos/snapshots.nix
    ../../modules/nixos/first-login.nix
    ../../modules/nixos/envs.nix # envs themselves are defined in the private flake
  ];

  networking.hostName = "precision";
  firstLogin.privateRepo = "DanielStott/nixos-private";
  firstLogin.githubAppClientId = "Iv23li7v3RCkVRA94bGq"; # DanielStott-nixos-setup (not a secret)

  users.users.stott = {
    isNormalUser = true;
    description = "Daniel Stott";
    extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    # The password is set once with `passwd` during install; nothing secret lives here.
  };

  # NixOS release this machine was first installed with. Never change it after install.
  system.stateVersion = "26.05";
}
