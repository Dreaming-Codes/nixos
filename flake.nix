{
  description = "NixOS system flake";

  inputs = {
    # NixOS official package source, using the nixos-unstable branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kwin-effects-forceblur = {
      url = "github:taj-ny/kwin-effects-forceblur";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-alien.url = "github:thiagokokada/nix-alien";
    garuda.url = "gitlab:garuda-linux/garuda-nix-subsystem/stable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, garuda, chaotic, ... }: {
    nixosConfigurations.DreamingDesk = garuda.lib.garudaSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [ ./configuration.nix
        {
            networking.hostName = "DreamingDesk";
        }
      ];
    };
    nixosConfigurations.DreamingBlade = garuda.lib.garudaSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [ ./configuration.nix
        ./hardware/razer-laptop.nix
        {
            networking.hostName = "DreamingBlade";
            powerManagement = {
                enable = true;
                powertop.enable = true;
            };
        }
      ];
    };
  };
}
