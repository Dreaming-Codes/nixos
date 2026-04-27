{pkgs, ...}: {
  hardware.bluetooth = {
    enable = true;
    disabledPlugins = ["sap"];
    settings = {
      General = {
        Experimental = true;
        KernelExperimental = true;
        FastConnectable = true;
        JustWorksRepairing = "always";
        MultiProfile = "multiple";
        Privacy = "device";
        RemoteNameRequestRetryDelay = 60;
      };
      LE = {
        MinConnectionInterval = 7;
        MaxConnectionInterval = 9;
        ConnectionLatency = 0;
        EnableAdvMonInterleaveScan = true;
      };
      AdvMon = {
        RSSISamplingPeriod = "0xFF";
      };
    };
  };

  # Intel AX210 SCO mic fix:
  # - enable_autosuspend=N: stops the controller from autosuspending mid-SCO,
  #   which breaks the isochronous USB alt-setting selection
  # - force_scofix=Y: forces the kernel to apply the SCO frame size fixup
  #   regardless of the controller's claimed quirks; without this the kernel
  #   leaves the SCO interface at alt 0 (no audio endpoint) on AX210 firmware.
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=N force_scofix=Y
  '';

  services.pipewire.wireplumber.extraConfig."51-bluez" = {
    "monitor.bluez.properties" = {
      # On Intel AX210 the USB-ISO SCO endpoint (alt 6) gets dropped by the
      # kernel mid-stream, breaking the mic. Routing SCO via HCI ("offload"
      # naming is misleading: it sends SCO frames over the HCI USB endpoint,
      # not the iso endpoint) avoids the alt-setting churn entirely.
      "bluez5.hw-offload-sco" = true;
      "bluez5.auto-connect" = [
        "hfp_hf"
        "hsp_hs"
      ];
    };
  };

  services.pipewire.wireplumber.extraConfig."52-bluez-suspend" = {
    "monitor.bluez.rules" = [
      {
        matches = [
          {"node.name" = "~bluez_input.*";}
          {"node.name" = "~bluez_output.*";}
        ];
        actions = {
          update-props = {
            "session.suspend-timeout-seconds" = 1;
            "node.pause-on-idle" = true;
          };
        };
      }
    ];
  };

  environment.systemPackages = [pkgs.overskride];
}
