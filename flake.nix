{
  description = "KooL's NixOS-Hyprland"; 
  	
  inputs = {
	#nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
  	nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    	
	#hyprland.url = "github:hyprwm/Hyprland"; # hyprland development
	#distro-grub-themes.url = "github:AdisonCavani/distro-grub-themes";

    quickshell = {
        url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
            inputs.nixpkgs.follows = "nixpkgs";
        };

  	};

  outputs = inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      host = "NixOS-Stott";
      username = "stott";
      installDisk = builtins.getEnv "installDisk" or "sda";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
    in
    {
      nixosConfigurations = {
        "${host}" = nixpkgs.lib.nixosSystem rec {
          specialArgs = { 
            inherit system;
            inherit inputs;
            inherit username;
            inherit host;
            inherit installDisk;
          };
          modules = [ 
            ./hosts/${host}/config.nix
            ./modules/quickshell.nix
            disko.nixosModules.disko
            ({ config, lib, ... }: {
              imports = [
                (import ./disko/disko.config.nix { disk = installDisk; })
              ];
            })
          ];
        };
      };
    };
}