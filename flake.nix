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
    nixpkgs-dreamingcodes.url = "github:Dreaming-Codes/nixpkgs/master";
    somo.url = "github:theopfr/somo?dir=nix";
    rip2 = {
      url = "github:MilesCranmer/rip2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-gpu-screen-recorder-ui.url = "github:js6pak/nixpkgs/gpu-screen-recorder-ui/init";
    dolphin-overlay.url = "github:rumboon/dolphin-overlay";
    astal = {
      url = "github:aylur/astal";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ags = {
      url = "github:aylur/ags";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprpanel.url = "github:Jas-SinghFSU/HyprPanel";
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    nix-alien.url = "github:thiagokokada/nix-alien";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    razer-laptop-controller = {
      url = "github:JosuGZ/razer-laptop-control-no-dkms";
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
    nixpkgs-dreamingcodes,
    razer-laptop-controller,
    rip2,
    home-manager,
    hyprpanel,
    chaotic,
    somo,
    ags,
    dolphin-overlay,
    nixpkgs-gpu-screen-recorder-ui,
    nix-index-database,
    astal,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    pkgsStable = import nixpkgs-stable {inherit system;};
    pkgsDreamingCodes = import nixpkgs-dreamingcodes {inherit system;};
    pkgsGpuScreenRecoderUi = import nixpkgs-gpu-screen-recorder-ui {inherit system;};

    specialArgs = {inherit inputs pkgsStable pkgsDreamingCodes pkgsGpuScreenRecoderUi astal ags hyprpanel dolphin-overlay home-manager nix-index-database rip2 somo;};
    commonModules = [
      ./configuration.nix
      home-manager.nixosModules.home-manager
      chaotic.nixosModules.default
    ];
  in {
    nixosConfigurations.DreamingDesk = nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      system = "x86_64-linux";
      modules =
        commonModules
        ++ [
          ./desktop.nix
          ./modules/virtualization
          {networking.hostName = "DreamingDesk";}
        ];
    };
    nixosConfigurations.DreamingBlade = nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      system = "x86_64-linux";
      modules =
        commonModules
        ++ [
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
