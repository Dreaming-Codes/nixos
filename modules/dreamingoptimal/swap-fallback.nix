{
  config,
  lib,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.swapFallback;
in {
  config = lib.mkIf cfg.enable {
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 16 * 1024;
        priority = 1;
      }
    ];
  };
}
