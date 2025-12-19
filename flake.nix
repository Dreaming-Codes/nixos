{
  description = "NixOS system flake";

  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
      "https://numtide.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    # NixOS official package source, using the nixos-unstable branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-davinci.url = "github:nixos/nixpkgs/d457818da697aa7711ff3599be23ab8850573a46";
    gauntlet = {
      url = "github:project-gauntlet/gauntlet";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dolphin-overlay.url = "github:rumboon/dolphin-overlay";
    nix-alien.url = "github:thiagokokada/nix-alien";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    razer-laptop-controller = {
      url = "github:JosuGZ/razer-laptop-control-no-dkms";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    vaultix.url = "github:milieuim/vaultix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    vaultix,
    razer-laptop-controller,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    lib = import ./lib/mkHost.nix {inherit inputs;};
  in {
    nixosConfigurations = {
      DreamingDesk = lib.mkHost {
        hostname = "DreamingDesk";
        hostPath = "dreamingdesk";
        extraModules = [
          # ./modules/programs/virtualization  # Enable when ready
        ];
      };

      DreamingBlade = lib.mkHost {
        hostname = "DreamingBlade";
        hostPath = "dreamingblade";
        extraModules = [
          razer-laptop-controller.nixosModules.default
          {
            powerManagement = {
              enable = true;
              powertop.enable = true;
            };
          }
        ];
      };
    };

    vaultix = vaultix.configure {
      nodes = self.nixosConfigurations;
      identity = self + "/opt/secret.age";
      extraRecipients = [];
      extraPackages = [];
      pinentryPackage = pkgs.kwalletcli;
      cache = "./secret/.cache";
    };
  };
}
