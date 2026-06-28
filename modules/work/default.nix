{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.work;
in {
  options.dreaming.work.enable = lib.mkEnableOption "work (Neuralink/Bedrock) tooling: opencode model + AWS profile";

  config = lib.mkIf cfg.enable {
    home-manager.users.dreamingcodes.imports = [../../home/work.nix];
  };
}
