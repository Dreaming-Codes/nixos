{
  config,
  pkgs,
  ...
}: {
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
    extraRules = [
      # ── Development tools ───────────────────────────────────────────────
      # rust-analyzer can spawn multiple instances and eat significant RAM.
      # Service type (like clangd), plus raised OOM score so the kernel
      # kills these before the desktop/editor under memory pressure.
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

      # ── Interactive tools ───────────────────────────────────────────────
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

      # ── Background system services ──────────────────────────────────────
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

      # ── Critical — must survive OOM ─────────────────────────────────────
      # ananicy-cpp (-999) and systemd-oomd (-900) already self-protect.
      # dockerd/containerd (-500) are set by Docker itself.
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
  boot.kernel.sysctl = {
    "kernel.nmi_watchdog" = 0;
    "kernel.sched_cfs_bandwidth_slice_us" = 3000;
    "net.core.rmem_max" = 2500000;
    "vm.max_map_count" = 16777216;
    # ZRAM is relatively cheap, prefer swap
    "vm.swappiness" = 180;
    # ZRAM is in memory, no need to readahead
    "vm.page-cluster" = 0;
  };
  services.bpftune.enable = true;
  zramSwap = {
    algorithm = "zstd";
    enable = true;
    memoryPercent = 90;
    priority = 100; # Higher priority - use zram first (faster, compressed RAM)
  };

  # Disk-based swap as fallback when zram is exhausted
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024; # 16GB in MB
      priority = 1; # Lower priority - only use when zram is full
    }
  ];
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;

  services.fstrim.enable = true;
}
