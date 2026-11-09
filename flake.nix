{
  description = "A minimal encrypted NixOS install that hands over to your private flake at first login";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      # install.sh writes machine.nix (your answers) and hardware.nix (what the installer
      # detected) next to this file on the new system. This repo has neither, so the example
      # stands in when it's built here.
      machine = import (if builtins.pathExists ./machine.nix then ./machine.nix else ./machine.example.nix);
    in
    {
      nixosConfigurations.installed = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit machine; };
        modules = [ ./modules/system.nix ./modules/first-login.nix ]
          ++ nixpkgs.lib.optional (builtins.pathExists ./hardware.nix) ./hardware.nix;
      };
    };
}
