{
  description = "NixOS for a Dell Precision 7680: a Hyprland + Noctalia base that installs from anywhere";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The cachix branch always points at a commit Noctalia's CI has already built.
    # Its nixpkgs is not overridden, so the binary cache matches.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";
  };

  nixConfig = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      mkHost = host: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs pkgs-unstable; };
        modules = [
          host
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
            home-manager.users.stott = import ./modules/home;
          }
        ];
      };
    in
    {
      # Reusable modules, imported by the private flake as well.
      nixosModules = {
        base = ./modules/nixos/base.nix;
        desktop = ./modules/nixos/desktop.nix;
        nvidia-prime = ./modules/nixos/nvidia-prime.nix;
        nvidia-off = ./modules/nixos/nvidia-off.nix;
        snapshots = ./modules/nixos/snapshots.nix;
        first-login = ./modules/nixos/first-login.nix;
      };
      homeModules.default = ./modules/home;

      # Stage 1: the complete base system, buildable with no private input.
      nixosConfigurations.precision = mkHost ./hosts/precision;

      # The same desktop in a VM, for trying changes before installing them.
      nixosConfigurations.precision-vm = mkHost ./hosts/precision-vm;
    };
}
