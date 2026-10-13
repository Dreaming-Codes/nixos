{...}: {
  perSystem = {pkgs, ...}: {
    packages.nix-file-overlay = pkgs.callPackage ../packages/nix-file-overlay {};
    packages.co2mon = pkgs.callPackage ../packages/co2mon {};
  };

  flake.overlays.default = final: _prev: {
    nix-file-overlay = final.callPackage ../packages/nix-file-overlay {};
    co2mon = final.callPackage ../packages/co2mon {};
  };
}
