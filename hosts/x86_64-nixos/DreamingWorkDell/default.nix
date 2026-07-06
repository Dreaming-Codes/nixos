{
  pkgs,
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

  # howdy (IR scanner) — face unlock
  services = {
    howdy = {
      enable = true;
    };
    linux-enable-ir-emitter.enable = true;
  };
  security.pam.howdy.enable = true;
  security.pam.services.login.howdy.enable = false;
  security.pam.services.greetd.howdy.enable = false;
  security.pam.services.dms-greeter.howdy.enable = false;
  security.pam.services.dankshell = {};
  security.pam.services.dankshell.rules.auth.howdy.control = lib.mkForce "sufficient";
  security.pam.services.dankshell.rules.auth.howdy.order = lib.mkForce 13000;
  services.fprintd.enable = true;
}
