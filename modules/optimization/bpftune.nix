{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.optimization.bpftune;
in {
  config = lib.mkIf cfg.enable {
    services.bpftune.enable = true;
  };
}
