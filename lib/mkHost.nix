{inputs, ...}: let
  commonModules = [
    inputs.nixos-facter-modules.nixosModules.facter
    inputs.nur.modules.nixos.default
    inputs.home-manager.nixosModules.home-manager
  ];
in {
  mkHost = {
    hostname,
    hostPath,
    system ? "x86_64-linux",
    extraModules ? [],
  }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        inherit (inputs) dolphin-overlay home-manager nix-index-database;
      };
      modules =
        commonModules
        ++ [
          ../hosts/common.nix
          ../hosts/${hostPath}
          {
            facter.reportPath = ../hosts/${hostPath}/facter.json;
            networking.hostName = hostname;
          }
        ]
        ++ extraModules;
    };
}
