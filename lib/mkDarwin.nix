{inputs, ...}: let
  commonModules = [
    inputs.determinate.darwinModules.default
    inputs.home-manager.darwinModules.home-manager
    ../modules/darwin/common.nix
  ];
in {
  mkDarwin = {
    hostname,
    hostPath,
    system ? "aarch64-darwin",
    extraModules ? [],
  }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        inherit
          (inputs)
          home-manager
          nix-index-database
          ;
      };
      modules =
        commonModules
        ++ [
          ../hosts/${hostPath}
          {networking.hostName = hostname;}
        ]
        ++ extraModules;
    };
}
