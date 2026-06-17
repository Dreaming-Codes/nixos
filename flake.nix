{
  description = "NixOS system flake";

  # Binary caches. This is the single source of truth; modules/core/nix.nix
  # imports this same attrset via `(import ./flake.nix).nixConfig`.
  # Note: per Nix flake spec, `nixConfig` must be a literal attrset — we cannot
  # compute it from JSON or another file, so the literal lives here.
  nixConfig = {
    substituters = [
      "https://install.determinate.systems?priority=20"
      "https://cache.nixos.org?priority=40"
      "https://nix-community.cachix.org?priority=41"
      "https://attic.xuyh0120.win/lantian?priority=42"
      "https://numtide.cachix.org?priority=43"
      "https://cache.nixos-cuda.org?priority=45"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-discord-vk.url = "github:LuckShiba/nixpkgs/discord-vk";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-davinci.url = "github:nixos/nixpkgs/d457818da697aa7711ff3599be23ab8850573a46";
    dms-plugin-registry = {
      url = "github:AvengeMedia/dms-plugin-registry";
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
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    razer-laptop-controller = {
      url = "github:JosuGZ/razer-laptop-control-no-dkms";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brave-origin.url = "github:Dreaming-Codes/nixpkgs/brave-channels";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    razer-laptop-controller,
    ...
  }: let
    mkHost = (import ./lib/mkHost.nix {inherit inputs;}).mkHost;
    mkDarwin = (import ./lib/mkDarwin.nix {inherit inputs;}).mkDarwin;
  in {
    nixosModules = {
      nix-file-overlay = ./modules/nix-file-overlay;
      dreamingoptimal = ./modules/dreamingoptimal;
      dreamingoptimal-ram = ./modules/dreamingoptimal/ram.nix;
      dreamingoptimal-swap-fallback = ./modules/dreamingoptimal/swap-fallback.nix;
      dreamingoptimal-process-tuning = ./modules/dreamingoptimal/process-tuning.nix;
      dreamingoptimal-sysctl = ./modules/dreamingoptimal/sysctl.nix;
      dreamingoptimal-bpftune = ./modules/dreamingoptimal/bpftune.nix;
      dreamingoptimal-cachykernel = ./modules/dreamingoptimal/cachykernel.nix;
      dreamingoptimal-fstrim = ./modules/dreamingoptimal/fstrim.nix;
      dreamingoptimal-envfs = ./modules/dreamingoptimal/envfs.nix;
    };

    hmModules = {
      nix-file-overlay = ./modules/nix-file-overlay/hm-module.nix;
    };

    nixosConfigurations = {
      DreamingDesk = mkHost {
        hostname = "DreamingDesk";
        hostPath = "dreamingdesk";
        extraModules = [
          # ./modules/programs/virtualization  # Enable when ready
        ];
      };

      DreamingBlade = mkHost {
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

      DreamingWork = mkHost {
        hostname = "DreamingWork";
        hostPath = "dreamingwork";
        system = "aarch64-linux";
        useFacter = false;
        extraModules = [
          inputs.apple-silicon.nixosModules.apple-silicon-support
        ];
      };
    };

    darwinConfigurations = {
      DreamingNeuraBook = mkDarwin {
        hostname = "DreamingNeuraBook";
        hostPath = "dreamingneurabook";
      };
    };
  };
}
