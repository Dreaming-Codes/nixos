{
  lib,
  config,
  ...
}: {
  imports = [./disk-config.nix];

  # Hardware report: hosts/x86_64-nixos/DreamingWorkDell/facter.json
  # (wired via flake-modules/hosts.nix). Regenerate with:
  #   sudo nixos-facter -o hosts/x86_64-nixos/DreamingWorkDell/facter.json
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

  # Hybrid Intel Arc iGPU + NVIDIA RTX 5000 Ada (see modules/hardware/optimus.nix).
  # Bus IDs from lspci: 00:02.0 Intel, 01:00.0 NVIDIA.
  dreaming.hardware.optimus = {
    enable = true;
    nvidiaBusId = "PCI:1:0:0";
    intelBusId = "PCI:0:2:0";
  };

  # Fingerprint for lock/sudo etc.; disabled at boot below (need password for fscrypt).
  services.fprintd.enable = true;
  # Boot/login: password only (no biometrics). Fingerprint is useless/harmful
  # at greeter with fscrypt home
  security.pam.services.login.fprintAuth = false;
  security.pam.services.greetd.fprintAuth = false;
  security.pam.services.dms-greeter.fprintAuth = false;
}
