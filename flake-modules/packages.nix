{...}: {
  perSystem = {pkgs, ...}: {
    packages.nix-file-overlay = pkgs.callPackage ../packages/nix-file-overlay {};
    packages.openlogi = pkgs.callPackage ../packages/openlogi {};
  };

  flake.overlays.default = final: _prev: {
    nix-file-overlay = final.callPackage ../packages/nix-file-overlay {};
    openlogi = final.callPackage ../packages/openlogi {};
  };
}
