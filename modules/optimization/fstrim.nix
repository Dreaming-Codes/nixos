{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.optimization.fstrim;
in {
  config = lib.mkIf cfg.enable {
    services.fstrim.enable = true;
  };
}
