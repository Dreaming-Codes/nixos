{...}: {
  perSystem = {pkgs, ...}: {
    packages.nix-file-overlay = pkgs.callPackage ../packages/nix-file-overlay {};
  };

  flake.overlays.default = final: _prev: {
    nix-file-overlay = final.callPackage ../packages/nix-file-overlay {};
  };
}
