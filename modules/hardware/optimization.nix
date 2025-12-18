{
  config,
  pkgs,
  ...
}: {
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
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
  };
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
}
