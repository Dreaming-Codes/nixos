{
  description = "NixOS system flake";

  # Public caches only. The n7k artifact-s3-gateway lives in modules/work
  # so personal hosts never see it via flake nixConfig / --accept-flake-config.
  nixConfig = {
    substituters = [
      "https://install.determinate.systems?priority=20"
      "https://cache.nixos.org?priority=40"
    ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nix-build-heaven = {
      url = "github:Dreaming-Codes/nix-build-heaven";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.determinate.follows = "determinate";
    };
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
    razer-laptop-controller = {
      url = "github:JosuGZ/razer-laptop-control-no-dkms";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    haumea = {
      url = "github:nix-community/haumea";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    easy-hosts.url = "github:tgirlcloud/easy-hosts";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    haumea,
    easy-hosts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      imports =
        [
          easy-hosts.flakeModule
        ]
        ++ builtins.attrValues (
          haumea.lib.load {
            src = ./flake-modules;
            loader = haumea.lib.loaders.path;
          }
        );
    };
}
