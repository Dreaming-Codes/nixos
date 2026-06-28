{
  description = "NixOS system flake";

  nixConfig = {
    substituters = [
      "https://artifact-s3-gateway.int.n7k.io/n7k-nix-cache?priority=10"
      "https://install.determinate.systems?priority=20"
      "https://cache.nixos.org?priority=40"
      "https://nix-community.cachix.org?priority=41"
      "https://attic.xuyh0120.win/lantian?priority=42"
      "https://numtide.cachix.org?priority=43"
      "https://cache.nixos-cuda.org?priority=45"
    ];
    extra-trusted-public-keys = [
      "nix-cache.infra.n7k.io-0:WyML6bRQeGqxs/1iSoQrlMuooDlxG15rgjuo7Elmpf4="
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
    paneru = {
      url = "github:karinushka/paneru";
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
        "aarch64-darwin"
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
