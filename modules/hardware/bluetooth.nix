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

  services.pipewire.wireplumber.extraConfig."51-bluez" = {
    "monitor.bluez.properties" = {
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
        matches = [{"device.name" = "~bluez_card.*";}];
        actions = {
          update-props = {
            "session.suspend-timeout-seconds" = 1;
            "bluez5.auto-connect" = false;
          };
        };
      }
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
