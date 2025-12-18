{
  pkgs,
  inputs,
  config,
  lib,
  ...
}: {
  boot.extraModulePackages = [
    config.boot.kernelPackages.ddcci-driver
    config.boot.kernelPackages.kvmfr
  ];
}
