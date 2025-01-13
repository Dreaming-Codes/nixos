{
  description = "NixOS system flake";

  nixConfig = {
    extra-substituters = [ "https://chaotic-nyx.cachix.org" ];
    extra-trusted-public-keys = [
      "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
    ];
  };

  inputs = {
    # NixOS official package source, using the nixos-unstable branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
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
    Neve = {
      url = "github:Dreaming-Codes/Neve";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-your-shell = {
      url = "github:MercuryTechnologies/nix-your-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, nixpkgs, nixpkgs-stable, nix-your-shell, garuda, chaotic, Neve, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      pkgsStable = import nixpkgs-stable { inherit system; };
    in {
      nixosConfigurations.DreamingDesk = garuda.lib.garudaSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs pkgsStable nix-your-shell; };
        modules = [
          ./configuration.nix
          ./desktop.nix
          { networking.hostName = "DreamingDesk"; }
        ];
      };
      nixosConfigurations.DreamingBlade = garuda.lib.garudaSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs pkgsStable nix-your-shell; };
        modules = [
          ./configuration.nix
          ./laptop.nix
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
