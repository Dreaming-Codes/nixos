{
  description = "NixOS system flake";

  nixConfig = {
    substituters = [
      "https://install.determinate.systems?priority=20"
      "https://cache.garnix.io?priority=30"
      "https://cache.nixos.org?priority=40"
      "https://nix-community.cachix.org?priority=41"
      "https://attic.xuyh0120.win/lantian?priority=42"
      "https://numtide.cachix.org?priority=43"
      "https://vicinae.cachix.org?priority=44"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    ];
  };

  inputs = {
    # NixOS official package source, using the nixos-unstable branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-davinci.url = "github:nixos/nixpkgs/d457818da697aa7711ff3599be23ab8850573a46";
    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vicinae-extensions = {
      url = "github:vicinaehq/extensions";
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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    razer-laptop-controller,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    lib = import ./lib/mkHost.nix {inherit inputs;};
  in {
    nixosModules = {
      dreamingoptimal = ./modules/dreamingoptimal;
      dreamingoptimal-ram = ./modules/dreamingoptimal/ram.nix;
      dreamingoptimal-tmp = ./modules/dreamingoptimal/tmp.nix;
      dreamingoptimal-swap-fallback = ./modules/dreamingoptimal/swap-fallback.nix;
      dreamingoptimal-process-tuning = ./modules/dreamingoptimal/process-tuning.nix;
      dreamingoptimal-sysctl = ./modules/dreamingoptimal/sysctl.nix;
      dreamingoptimal-bpftune = ./modules/dreamingoptimal/bpftune.nix;
      dreamingoptimal-cachykernel = ./modules/dreamingoptimal/cachykernel.nix;
      dreamingoptimal-fstrim = ./modules/dreamingoptimal/fstrim.nix;
    };

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
  };
}
