{
  config,
  lib,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.sysctl;
in {
  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl = {
      "kernel.nmi_watchdog" = 0;
      "kernel.sched_cfs_bandwidth_slice_us" = 3000;
      "net.core.rmem_max" = 2500000;
      "vm.max_map_count" = 16777216;
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "kernel.unprivileged_userns_clone" = 1;
    };
  };
}
