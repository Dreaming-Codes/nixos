{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [./disk-config.nix];

  # TODO: Generate the real hardware report on the Dell and place it here:
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

  # Intel iGPU only — Mesa handles display/graphics/VAAPI.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = ["modesetting"];

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
