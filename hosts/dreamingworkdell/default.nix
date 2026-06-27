{
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    ../common-x86.nix
  ];

  # TODO: Generate the real hardware report on the Dell and place it here:
  #   sudo nixos-facter -o hosts/dreamingworkdell/facter.json
  # Until then the values below are placeholders and MUST be corrected
  # before deploying to real hardware.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usb_storage"
    "usbhid"
    "sd_mod"
  ];

  # TODO: Replace placeholder UUIDs with the real ones from the Dell:
  #   lsblk -f   (or)   blkid
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0000-0000";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

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
