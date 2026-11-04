{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.dreaming.hardware.galaxybook6-camera;
  pkgDir = self + "/packages/galaxybook6-camera";
  kernelPackages = config.boot.kernelPackages;

  sensorModules = kernelPackages.callPackage pkgDir {};
  psys = kernelPackages.callPackage (pkgDir + "/psys.nix") {};
  hal = pkgs.callPackage (pkgDir + "/ipu7-hal.nix") {};
  icamerasrc = pkgs.callPackage (pkgDir + "/icamerasrc.nix") {inherit hal;};
  cameraLabel = "Built-in Front Camera";
in {
  options.dreaming.hardware.galaxybook6-camera = {
    enable = lib.mkEnableOption ''
      Samsung Galaxy Book6 Ultra built-in camera (IPU7 + SC200PC / ACPI SSLC2000)
      through the IPU7 hardware ISP and Intel's camera HAL with Samsung's tuning
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.pipewire.wireplumber.enable;
        message = "dreaming.hardware.galaxybook6-camera requires services.pipewire.wireplumber.enable";
      }
    ];

    boot.extraModulePackages = [sensorModules psys];
    boot.kernelModules = ["ipu_bridge" "sc200pc"];

    services.udev.extraRules = ''
      KERNEL=="ipu7-psys[0-9]*", GROUP="video", MODE="0660"
    '';

    # The HAL stores AIQ calibration data here and never creates the directory.
    systemd.tmpfiles.rules = ["d /run/camera 0755 root root -"];

    services.v4l2-relayd.instances.sc200pc = {
      enable = true;
      cardLabel = cameraLabel;
      extraPackages = [icamerasrc];
      input = {
        # Caps come from the relay's appsink, built from the fields below.
        pipeline = "icamerasrc device-name=sc200pc-uf";
        format = "NV12";
        width = 1920;
        height = 1080;
        framerate = 30;
      };
      # Pass the HAL's NV12 through; the default YUY2 costs a CPU conversion per frame.
      output.format = "NV12";
    };

    # nixpkgs creates the loopback with exclusive caps, so it reports
    # output-only until the relay writes, and WirePlumber probes it before
    # that and creates no Source. Deleting it on stop fails while WirePlumber
    # holds it open, so reuse it by label instead of leaking one per restart.
    systemd.services.v4l2-relayd-sc200pc = {
      preStart = lib.mkForce ''
        mkdir -p "$(dirname "$V4L2_DEVICE_FILE")"
        for name in /sys/class/video4linux/*/name; do
          if [ "$(cat "$name")" = "${cameraLabel}" ]; then
            echo "/dev/$(basename "$(dirname "$name")")" > "$V4L2_DEVICE_FILE"
            exit 0
          fi
        done
        ${kernelPackages.v4l2loopback.bin}/bin/v4l2loopback-ctl add -x 0 \
          -b ${toString config.services.v4l2-relayd.instances.sc200pc.bufferCount} \
          -n "${cameraLabel}" > "$V4L2_DEVICE_FILE"
      '';
      postStop = lib.mkForce "";
    };

    services.pipewire.wireplumber.extraConfig = {
      # Raw IPU7 ISYS Bayer nodes are unusable without an ISP. api.v4l2.cap.*
      # is not yet populated when device rules run, so match the PCI path.
      "50-ipu7-hide-v4l2"."monitor.v4l2.rules" = [
        {
          matches = [
            {"device.name" = "~v4l2_device.pci-0000_00_05.0*";}
          ];
          actions.update-props."device.disabled" = true;
        }
      ];
      # The relay owns the sensor; a libcamera source would compete for it.
      "51-ipu7-isp"."wireplumber.profiles".main."monitor.libcamera" = "disabled";
    };
  };
}
