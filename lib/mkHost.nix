{inputs, ...}: let
  commonModules = [
    inputs.nur.modules.nixos.default
    inputs.home-manager.nixosModules.home-manager
    inputs.dms-plugin-registry.nixosModules.default
    inputs.determinate.nixosModules.default
    inputs.sops-nix.nixosModules.sops
    ../modules/dreamingoptimal
    ../modules/nix-file-overlay
  ];
in {
  mkHost = {
    hostname,
    hostPath,
    system ? "x86_64-linux",
    useFacter ? true,
    extraModules ? [],
  }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        inherit
          (inputs)
          dolphin-overlay
          home-manager
          nix-index-database
          ;
      };
      modules =
        commonModules
        ++ inputs.nixpkgs.lib.optionals useFacter [
          inputs.nixos-facter-modules.nixosModules.facter
          {facter.reportPath = ../hosts/${hostPath}/facter.json;}
        ]
        ++ [
          ../hosts/common-base.nix
          ../hosts/${hostPath}
          {
            networking.hostName = hostname;
          }
        ]
        ++ extraModules;
    };
}
