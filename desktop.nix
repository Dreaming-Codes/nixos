{ pkgs, ... }:
let
  steam-run-url = pkgs.writeShellApplication {
    name = "steam-run-url";
    text = ''
      echo "$1" > "/run/user/$(id --user)/steam-run-url.fifo"
    '';
    runtimeInputs = [
      pkgs.coreutils # For `id` command
    ];
  };
in {
  environment.systemPackages = with pkgs; [
    # amd gpu utility
    lact
    # amd encoders/decoders
    amf
    looking-glass-client
    steam-run-url
    xorg.libxcvt
  ];

  systemd.user.services.steam-run-url-service = {
    enable = true;
    description = "Listen and starts steam games by id";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig.Restart = "on-failure";
    script = toString (pkgs.writers.writePython3 "steam-run-url-service" { } ''
      import os
      from pathlib import Path
      import subprocess

      pipe_path = Path(f'/run/user/{os.getuid()}/steam-run-url.fifo')
      try:
          pipe_path.parent.mkdir(parents=True, exist_ok=True)
          pipe_path.unlink(missing_ok=True)
          os.mkfifo(pipe_path, 0o600)
          while True:
              with pipe_path.open(encoding='utf-8') as pipe:
                  subprocess.Popen(['steam', pipe.read().strip()])
      finally:
          pipe_path.unlink(missing_ok=True)
    '');
    path = [ pkgs.steam ];
  };

  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
  systemd.user.services.sunshine.path = [ steam-run-url ];
  services.avahi.publish.enable = true;
  services.avahi.publish.userServices = true;

  virtualisation.waydroid.enable = true;

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
  boot.blacklistedKernelModules = [ "nouveau" ];

  nixpkgs.config.rocmSupport = true;

  hardware.graphics = {
    # Mesa
    enable = true;

    enable32Bit = true;

    extraPackages = with pkgs; [ rocmPackages.clr.icd amdvlk ];
    extraPackages32 = with pkgs; [ driversi686Linux.amdvlk ];
  };

  environment.variables = {
    # always prefer radv
    AMD_VULKAN_ICD = "RADV";
  };

  systemd.services.lact = {
    description = "AMDGPU Control Daemon";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { ExecStart = "${pkgs.lact}/bin/lact daemon"; };
    enable = true;
  };

  # Fix for AMDGPU
  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [ rocblas hipblas clr ];
    };
  in [
    "L+    /opt/rocm   -    -    -     -    ${rocmEnv}"
    "f /dev/shm/looking-glass 0660 dreamingcodes kvm -"
  ];

  # 1. fix suspend
  # 2. make xremap work
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x06ed", ATTR{power/wakeup}="disabled"
    KERNEL=="uinput", GROUP="input", TAG+="uaccess"
  '';

  # Allow input devices to be accessed by dreamingcodes user (needed for xremap)
  users.users.dreamingcodes.extraGroups = [ "input" ];

  boot.kernelParams = [
    "pcie_acs_override=downstream"
    "intel_iommu=on"
    "iommu=pt"
    "amdgpu.ppfeaturemask=0xFFF7FFFF"
    ''vfio-pci.ids="10de:1b81,10de:10f0"''
  ];
}
