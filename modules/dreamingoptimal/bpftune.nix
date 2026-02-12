{
  config,
  lib,
  ...
}: let
  cfg = config.dreamingoptimal.optimization.bpftune;
in {
  config = lib.mkIf cfg.enable {
    services.bpftune.enable = true;
  };
}
