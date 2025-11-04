{
  description = "NixOS system flake";

  nixConfig = {
    extra-substituters = [
      "https://chaotic-nyx.cachix.org"
      "https://cache.garnix.io"
      "https://numtide.cachix.org"
    ];
    extra-trusted-public-keys = [
      "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
    ];
  };

  inputs = {
    # NixOS official package source, using the nixos-unstable branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-davinci.url = "github:nixos/nixpkgs/d457818da697aa7711ff3599be23ab8850573a46";
    nixpkgs-dreamingcodes.url = "github:Dreaming-Codes/nixpkgs/master";
    gauntlet = {
      url = "github:project-gauntlet/gauntlet";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    vaultix.url = "github:milieuim/vaultix";
    winboat.url = "github:TibixDev/winboat";
  };

  outputs = inputs @ {
    self,
    gauntlet,
    nixpkgs,
    nixpkgs-stable,
    nixpkgs-dreamingcodes,
    razer-laptop-controller,
    rip2,
    home-manager,
    chaotic,
    dolphin-overlay,
    nixpkgs-gpu-screen-recorder-ui,
    nix-index-database,
    vaultix,
    winboat,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    pkgsStable = import nixpkgs-stable {inherit system;};
    pkgsDreamingCodes = import nixpkgs-dreamingcodes {inherit system;};
    pkgsGpuScreenRecoderUi = import nixpkgs-gpu-screen-recorder-ui {inherit system;};

    specialArgs = {inherit inputs pkgsStable pkgsDreamingCodes pkgsGpuScreenRecoderUi dolphin-overlay home-manager nix-index-database rip2 gauntlet winboat;};
    commonModules = [
      inputs.nixos-facter-modules.nixosModules.facter
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
          {config.facter.reportPath = ./facter-dreamingdesk.json;}
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
          {config.facter.reportPath = ./facter-dreamingblade.json;}
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
