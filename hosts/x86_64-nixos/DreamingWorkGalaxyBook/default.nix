{
  lib,
  config,
  ...
}: {
  imports = [
    ./disk-config.nix
    ./display-profiles.nix
  ];

  # Samsung Galaxy Book6 Ultra (Panther Lake).
  # Hardware report: hosts/x86_64-nixos/DreamingWorkGalaxyBook/facter.json
  # (wired via flake-modules/hosts.nix). Regenerate with:
  #   sudo nixos-facter -o hosts/x86_64-nixos/DreamingWorkGalaxyBook/facter.json

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.loader.limine.efiInstallAsRemovable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  # Intel Arc B390 iGPU only, no dGPU.
  hardware.graphics.enable = true;

  # Webcam is Intel IPU7 (no nixpkgs support yet) and the fingerprint reader is
  # an Egis sensor needing a patched libfprint, so neither is configured.
}
