{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.cachykernel;
in {
  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [inputs.nix-cachyos-kernel.overlays.pinned];
    boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
  };
}
