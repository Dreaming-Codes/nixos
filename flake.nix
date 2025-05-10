{
  description = "NixOS system flake";

  nixConfig = {
    extra-substituters = [
      "https://chaotic-nyx.cachix.org"
      "https://nix-mirror.freetls.fastly.net"
      "https://anyrun.cachix.org"
      "https://hyprland.cachix.org"
      "https://helix.cachix.org"
    ];
    extra-trusted-public-keys = [
      "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
      "anyrun.cachix.org-1:pqBobmOjI7nKlsUMV25u9QHa9btJK65/C8vnO3p346s="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
    ];
  };

  inputs = {
    # NixOS official package source, using the nixos-unstable branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    nix-alien.url = "github:thiagokokada/nix-alien";
    garuda.url = "gitlab:garuda-linux/garuda-nix-subsystem/stable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nixos-vfio.url = "github:Stefanuk12/nixos-vfio/patch-1";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    razer-laptop-controller = {
      url = "github:JosuGZ/razer-laptop-control-no-dkms";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-your-shell = {
      url = "github:MercuryTechnologies/nix-your-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    anyrun = {
      url = "github:anyrun-org/anyrun";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix = {
      url = "github:helix-editor/helix";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixpkgs-stable,
    nix-your-shell,
    razer-laptop-controller,
    garuda,
    chaotic,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    pkgsStable = import nixpkgs-stable {inherit system;};
  in {
    nixosConfigurations.DreamingDesk = garuda.lib.garudaSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs pkgsStable nix-your-shell;};
      modules = [
        ./configuration.nix
        ./desktop.nix
        {networking.hostName = "DreamingDesk";}
      ];
    };
    nixosConfigurations.DreamingBlade = garuda.lib.garudaSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs pkgsStable nix-your-shell;};
      modules = [
        ./configuration.nix
        razer-laptop-controller.nixosModules.default
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
