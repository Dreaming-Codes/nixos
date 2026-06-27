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

  home-manager.users.dreamingcodes = {
    wayland.windowManager.hyprland = {
      settings = {
        bindl = [
          ",switch:off:Lid Switch, exec, dms ipc call lock lock"
        ];
        # TODO: Adjust to the Dell's panel and any external monitors.
        monitor = [
          "eDP-1, preferred, 0x0, 1"
          ", preferred, auto, 1"
        ];
        workspace = [
          "11, defaultName:F1"
          "12, defaultName:F2"
          "13, defaultName:F3"
          "14, defaultName:F4"
          "15, defaultName:F5"
          "16, defaultName:F6"
          "17, defaultName:F7"
          "18, defaultName:F8"
          "19, defaultName:F9"
          "20, defaultName:F10"
          "21, defaultName:F11"
          "22, defaultName:F12"
        ];
      };
    };
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
