{
  description = "KooL's NixOS-Hyprland"; 
  	
  inputs = {
	nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  	#nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

	
	#hyprland.url = "github:hyprwm/Hyprland"; # hyprland development
	#distro-grub-themes.url = "github:AdisonCavani/distro-grub-themes";
	ags.url = "github:aylur/ags/v1"; # aylurs-gtk-shell-v1
  	};

  outputs = 
	inputs@{ self, nixpkgs, ... }:
    	let
      system = "x86_64-linux";
      host = "NixOS-Stott";
      username = "stott";

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
			};
	   		modules = [ 
				./hosts/${host}/config.nix 
			    disko.nixosModules.disko	
				# inputs.distro-grub-themes.nixosModules.${system}.default
				];
			};
		};
	};
}
