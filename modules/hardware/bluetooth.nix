{...}: {
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
      # AX210: keep hw-offload disabled. Kernel always routes SCO via the USB
      # ISO endpoint (alt 6), and force_scofix=Y + enable_autosuspend=N keeps
      # that endpoint active.
      "bluez5.hw-offload-sco" = false;
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
          {"node.name" = "~bluez_output.*";}
        ];
        actions = {
          update-props = {
            # Quick suspend on output to avoid stealing A2DP from phone in
            # multipoint when nothing is actually playing on Linux.
            "session.suspend-timeout-seconds" = 2;
            "node.pause-on-idle" = true;
          };
        };
      }
      {
        matches = [
          {"node.name" = "~bluez_input.*";}
        ];
        actions = {
          update-props = {
            # Keep mic SCO link alive longer; tearing it down too quickly
            # causes alt-setting churn on AX210 and breaks recording when
            # the input pipeline (e.g. EasyEffects) briefly idles.
            "session.suspend-timeout-seconds" = 30;
            "node.pause-on-idle" = false;
          };
        };
      }
    ];
  };
}
