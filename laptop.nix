{
  pkgs,
  lib,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [nrfutil];
  nixpkgs.config.segger-jlink.acceptLicense = true;
  services = {
    udev = {
      extraRules = ''
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1915", ATTRS{idProduct}=="522a", ATTRS{serial}=="84014353616C81E9", GROUP="wireshark", MODE="0666"
      '';
    };
  };
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  home-manager.users.dreamingcodes = {
    wayland.windowManager.hyprland = {
      settings = {
        env = [
          "AQ_DRM_DEVICES,/dev/dri/card0:/dev/dri/card1"
        ];
        monitor = [
          "eDP-1, 1920x1080@60, 0x0, 1"
        ];
      };
    };
  };

  services.razer-laptop-control.enable = true;
  # Enable rocm support for the iGPU on the laptop
  nixpkgs.config.rocmSupport = true;
  # Enable cuda support for the dGPU on the laptop
  nixpkgs.config.cudaSupport = true;

  users = {users.dreamingcodes = {extraGroups = ["wireshark"];};};

  boot.kernelModules = ["kvm-amd"];
  boot.kernelParams = ["nvidia.NVreg_PreserveVideoMemoryAllocations=1"];

  ### Nvidia STUFF
  hardware.graphics = {
    enable = true;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = ["nvidia" "amdgpu"];

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = true;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    # Currently alpha-quality/buggy, so false is currently the recommended setting.
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = false;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    nvidiaBusId = "PCI:1:0:0";
    amdgpuBusId = "PCI:4:0:0";
  };

  specialisation = {
    no-gpu.configuration = {
      system.nixos.tags = ["no-gpu"];
      boot.extraModprobeConfig = ''
        blacklist nouveau
        options nouveau modeset=0
      '';
      services.udev.extraRules = ''
        # Remove NVIDIA USB xHCI Host Controller devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c0330", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA USB Type-C UCSI devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x0c8000", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA Audio devices, if present
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
        # Remove NVIDIA VGA/3D controller devices
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
      '';
      boot.blacklistedKernelModules = ["nouveau" "nvidia" "nvidia_drm" "nvidia_modeset"];
    };
    performance.configuration = {
      system.nixos.tags = ["performance"];
      hardware.nvidia = {
        powerManagement.finegrained = lib.mkForce false;
        prime.offload.enable = lib.mkForce false;
        prime.offload.enableOffloadCmd = lib.mkForce false;
        prime.sync.enable = lib.mkForce true;
      };
    };
    reverse.configuration = {
      system.nixos.tags = ["reverse"];
      hardware.nvidia = {
        powerManagement.finegrained = lib.mkForce false;
        prime.offload.enable = lib.mkForce false;
        prime.offload.enableOffloadCmd = lib.mkForce false;
        prime.sync.enable = lib.mkForce false;
        prime.reverseSync.enable = lib.mkForce true;
      };
    };
  };
}
