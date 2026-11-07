{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.dreaming.services.hermes;
in {
  imports = [inputs.hermes-agent.nixosModules.default];

  options.dreaming.services.hermes.enable =
    lib.mkEnableOption "Hermes Agent OCI container mode"
    // {
      default = false;
    };

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      container = {
        enable = true;
        backend = "docker";
        hostUsers = ["dreamingcodes"];
      };
    };
  };
}
