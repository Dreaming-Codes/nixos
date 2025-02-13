{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # amd gpu utility
    lact
    # amd encoders/decoders
    amf
    looking-glass-client
    via
  ];

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
  services.avahi.publish.enable = true;
  services.avahi.publish.userServices = true;

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
  boot.blacklistedKernelModules = ["nouveau"];

  nixpkgs.config.rocmSupport = true;

  hardware.graphics = {
    # Mesa
    enable = true;

    enable32Bit = true;

    extraPackages = with pkgs; [rocmPackages.clr.icd amdvlk amf];
    extraPackages32 = with pkgs; [driversi686Linux.amdvlk];
  };

  environment.variables = {
    # always prefer radv
    AMD_VULKAN_ICD = "RADV";
  };

  systemd.services.lact = {
    description = "AMDGPU Control Daemon";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {ExecStart = "${pkgs.lact}/bin/lact daemon";};
    enable = true;
  };

  # Fix for AMDGPU - Disabled cause it fails to build as of 30/01/2025
  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [rocblas hipblas clr];
    };
  in [
    "L+    /opt/rocm   -    -    -     -    ${rocmEnv}"
    "f /dev/shm/looking-glass 0660 dreamingcodes kvm -"
  ];

  hardware.keyboard.qmk.enable = true;
  services.udev.packages = [pkgs.via];
  # 1. fix suspend
  # 2. make xremap work
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x06ed", ATTR{power/wakeup}="disabled"
    KERNEL=="uinput", GROUP="input", TAG+="uaccess"
    SUBSYSTEM=="input", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="0660", MODE="0660", TAG+="uaccess"
  '';

  # Allow input devices to be accessed by dreamingcodes user (needed for xremap)
  users.users.dreamingcodes.extraGroups = ["input"];

  boot.kernelParams = [
    "pcie_acs_override=downstream"
    "intel_iommu=on"
    "iommu=pt"
    "amdgpu.ppfeaturemask=0xFFF7FFFF"
    ''vfio-pci.ids="10de:1b81,10de:10f0"''
  ];
}
