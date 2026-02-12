{
  config,
  lib,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.ram;
in {
  config = lib.mkIf cfg.enable {
    zramSwap = {
      algorithm = "zstd";
      enable = true;
      memoryPercent = 90;
      priority = 100;
    };
  };
}
