{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.processTuning;
in {
  config = lib.mkIf cfg.enable {
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp;
      rulesProvider = pkgs.ananicy-rules-cachyos;
      extraRules = [
        {
          name = "rust-analyzer";
          type = "Service";
          oom_score_adj = 300;
        }
        {
          name = "rust-analyzer-p";
          type = "Service";
          oom_score_adj = 300;
        }
        {
          name = "sccache";
          type = "BG_CPUIO";
        }
        {
          name = "opencode";
          type = "Doc-View";
        }
        {
          name = "gitui";
          type = "Doc-View";
        }
        {
          name = "helium";
          type = "Doc-View";
        }
        {
          name = "helium_crashpad";
          type = "BG_CPUIO";
        }
        {
          name = "zellij";
          type = "Doc-View";
        }
        {
          name = "fish";
          type = "Doc-View";
        }
        {
          name = "ashell";
          type = "LowLatency_RT";
        }
        {
          name = "ssh";
          type = "LowLatency_RT";
        }
        {
          name = "ModemManager";
          type = "BG_CPUIO";
        }
        {
          name = "wpa_supplicant";
          type = "BG_CPUIO";
        }
        {
          name = "nmbd";
          type = "BG_CPUIO";
        }
        {
          name = "winbindd";
          type = "BG_CPUIO";
        }
        {
          name = "wb-idmap";
          type = "BG_CPUIO";
        }
        {
          name = "smbd-cleanupd";
          type = "BG_CPUIO";
        }
        {
          name = "smbd-notifyd";
          type = "BG_CPUIO";
        }
        {
          name = "accounts-daemon";
          type = "Service";
        }
        {
          name = "nsncd";
          type = "Service";
        }
        {
          name = "acpid";
          type = "Service";
        }
        {
          name = "automatic-timez";
          type = "Service";
        }
        {
          name = "usbmuxd";
          type = "Service";
        }
        {
          name = "psimon";
          type = "BG_CPUIO";
        }
        {
          name = "razer-power";
          type = "BG_CPUIO";
        }
        {
          name = "ci-keyboard-led";
          type = "Service";
        }
        {
          name = "wl-clip-persist";
          type = "Service";
        }
        {
          name = "determinate-nix";
          type = "BG_CPUIO";
        }
        {
          name = "mount.envfs";
          type = "Service";
        }
        {
          name = "vicinae";
          type = "Service";
        }
        {
          name = "warp-svc";
          type = "IN_DIFF";
        }
        {
          name = "warp-taskbar";
          type = "IN_DIFF";
        }
        {
          name = "watchdogd";
          type = "Service";
          oom_score_adj = -1000;
        }
      ];
    };

    systemd.oomd = {
      enable = true;
      enableRootSlice = true;
      enableUserSlices = true;
      enableSystemSlice = true;
      settings.OOM = {
        "DefaultMemoryPressureDurationSec" = "20s";
      };
    };
  };
}
