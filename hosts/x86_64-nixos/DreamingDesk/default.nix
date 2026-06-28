{
  pkgs,
  lib,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [
    # amd gpu utility
    lact
    # amd encoders/decoders
    amf
  ];

  boot.kernelModules = ["kvm-intel"];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/059dc105-5a7a-4c4c-967c-af7bc6c7dd1a";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/FF73-5BE2";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.sunshine = {
    enable = true;
    autoStart = false;
    capSysAdmin = true;
    openFirewall = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.dreamingcodes.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAVaA+L9bwCFPsPztLCjPa8V/vYgTuXVeEP55LcXS/vi"
  ];

  # Additional kernel modules needed for virtualization
  boot.initrd.availableKernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
    "ahci"
    "usb_storage"
    "sd_mod"
    "amdgpu"
  ];
  # Blacklist nvidia gpu driver to prevent use
  boot.blacklistedKernelModules = [
    "nouveau"
    "nvidia"
  ];

  nixpkgs.config.rocmSupport = true;

  hardware.graphics = {
    # Mesa
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
      amf
    ];
  };

  environment.variables = {
    # always prefer radv
    AMD_VULKAN_ICD = "RADV";
  };

  systemd.services.lact = {
    description = "AMDGPU Control Daemon";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.lact}/bin/lact daemon";
    };
    enable = true;
  };

  # Fix for AMDGPU - Disabled cause it fails to build as of 30/01/2025
  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [
        rocblas
        hipblas
        clr
      ];
    };
  in [
    "L+    /opt/rocm   -    -    -     -    ${rocmEnv}"
    # Allow dreamingcodes full access to riccardo's home via ACL
    "A+ /home/riccardo - - - - u:dreamingcodes:rwx"
    "A+ /home/riccardo - - - - d:u:dreamingcodes:rwx"
  ];

  # 1. fix suspend
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x06ed", ATTR{power/wakeup}="disabled"
  '';

  boot.kernelParams = [
    "pcie_acs_override=downstream"
    "intel_iommu=on"
    "iommu=pt"
    "amdgpu.ppfeaturemask=0xFFF7FFFF"
    ''vfio-pci.ids="10de:1b81,10de:10f0"''
  ];
}
