{
  lib,
  config,
  ...
}: {
  imports = [
    ./disk-config.nix
    ./display-profiles.nix
  ];

  # Samsung Galaxy Book6 Ultra (Panther Lake). Hardware report is wired in
  # flake-modules/hosts.nix once it exists; generate it on the machine with:
  #   sudo nixos-facter -o hosts/x86_64-nixos/DreamingWorkGalaxyBook/facter.json
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.kernelModules = ["kvm-intel"];

  # Intel Arc B390 iGPU only, no dGPU.
  hardware.graphics.enable = true;

  # Webcam is Intel IPU7 (no nixpkgs support yet) and the fingerprint reader is
  # an Egis sensor needing a patched libfprint, so neither is configured.
}
