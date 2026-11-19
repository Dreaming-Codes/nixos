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
  nntm = pkgs.callPackage (pkgDir + "/nntm") {};
  cameraLabel = "Built-in Front Camera";
  relay = config.services.v4l2-relayd.instances.sc200pc;
  v4l2-ctl = "${pkgs.v4l-utils}/bin/v4l2-ctl";
in {
  options.dreaming.hardware.galaxybook6-camera = {
    enable = lib.mkEnableOption ''
      Samsung Galaxy Book6 Ultra built-in camera (IPU7 + SC200PC / ACPI SSLC2000)
      through the IPU7 hardware ISP and Intel's camera HAL with Samsung's tuning
    '';

    neuralToneMap = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the local tone mapping network of Samsung's Windows driver on every frame, as
        Windows does: Samsung's kernels and the network on the integrated GPU through OpenCL and
        OpenVINO. If the GPU back end cannot start it falls back to the CPU, which keeps most of
        one core busy while the camera is on.
      '';
    };
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
      extraPackages = [icamerasrc] ++ lib.optional cfg.neuralToneMap nntm;
      input = {
        # Caps come from the relay's appsink, built from the fields below.
        pipeline =
          "icamerasrc device-name=sc200pc-uf"
          + lib.optionalString cfg.neuralToneMap " ! nntm range=limited";
        format = "NV12";
        width = 1920;
        height = 1080;
        framerate = 30;
      };
    };

    # nixpkgs creates the loopback with exclusive caps, so it reports
    # output-only until the relay writes, and WirePlumber probes it before
    # that and creates no Source. Deleting it on stop fails while WirePlumber
    # holds it open, so reuse it by label instead of leaking one per restart.
    systemd.services.v4l2-relayd-sc200pc = {
      preStart = lib.mkForce ''
        mkdir -p "$(dirname "$V4L2_DEVICE_FILE")"
        device=
        for name in /sys/class/video4linux/*/name; do
          if [ "$(cat "$name")" = "${cameraLabel}" ]; then
            device="/dev/$(basename "$(dirname "$name")")"
            break
          fi
        done
        if [ -z "$device" ]; then
          device=$(${kernelPackages.v4l2loopback.bin}/bin/v4l2loopback-ctl add -x 0 \
            -b ${toString relay.bufferCount} -n "${cameraLabel}")
        fi
        # Fix the format the relay writes, BT.709 limited range included, so the device keeps reporting it
        # while the relay restarts. v4l2loopback only takes new colour fields together with a new size or
        # pixel format, so a reused device would otherwise keep whatever colours were written first.
        ${v4l2-ctl} -d "$device" --set-ctrl=keep_format=0
        ${v4l2-ctl} -d "$device" --set-fmt-video-out=width=640,height=480,pixelformat=YUYV
        ${v4l2-ctl} -d "$device" --set-fmt-video-out=width=${toString relay.input.width},height=${toString relay.input.height},pixelformat=NV12,colorspace=rec709,xfer=rec709,ycbcr=709,quantization=lim-range
        ${v4l2-ctl} -d "$device" --set-ctrl=keep_format=1
        echo "$device" > "$V4L2_DEVICE_FILE"
      '';
      # The HAL emits BT.709 limited range. Unlabelled, v4l2sink takes the loopback's BT.601 default and
      # videoconvert converts every frame; labelled, it passes the HAL's buffers through. icamerasrc frees
      # those buffers when the camera stops, so the sink must not keep the last one past that.
      script = lib.mkForce ''
        exec ${pkgs.v4l2-relayd}/bin/v4l2-relayd -i "${relay.input.pipeline}" -o "appsrc name=appsrc caps=video/x-raw,format=${relay.input.format},colorimetry=bt709,width=${toString relay.input.width},height=${toString relay.input.height},framerate=${toString relay.input.framerate}/1 ! videoconvert ! v4l2sink name=v4l2sink enable-last-sample=false device=$(cat $V4L2_DEVICE_FILE)"
      '';
      postStop = lib.mkForce "";
      # The HAL logs to stdout, which is block-buffered into the journal: lines arrive in 4 KB
      # blocks, up to an hour late.
      environment =
        {
          LD_PRELOAD = "${pkgs.coreutils}/libexec/coreutils/libstdbuf.so";
          _STDBUF_O = "L";
          # The HAL's face detector runs on the NPU, whose Level Zero driver is not on the library path.
          ZE_ENABLE_ALT_DRIVERS = "${pkgs.intel-npu-driver}/lib/libze_intel_npu.so.1";
          # The NPU driver caches compiled models only under HOME, which the unit does not set.
          HOME = "/var/cache/v4l2-relayd-sc200pc";
        }
        // lib.optionalAttrs cfg.neuralToneMap {
          OCL_ICD_VENDORS = "${pkgs.intel-compute-runtime}/etc/OpenCL/vendors";
          # The unit has no HOME, so the runtime would recompile the GPU kernels on every camera open.
          NEO_CACHE_DIR = "/var/cache/v4l2-relayd-sc200pc";
        };
      serviceConfig.CacheDirectory = "v4l2-relayd-sc200pc";
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
