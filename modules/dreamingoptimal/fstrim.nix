{
  config,
  lib,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.fstrim;
in {
  config = lib.mkIf cfg.enable {
    services.fstrim.enable = true;
  };
}
