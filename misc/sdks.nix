{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mapAttrs' mkEnableOption mkIf mkOption nameValuePair types;

  cfg = config.custom.misc.sdks;

  sdksDirectory = "/nixos/.sdks";
in {
  ###### interface

  options = {
    custom.misc.sdks = {
      enable = mkEnableOption "sdk links";

      links = mkOption {
        type = types.attrs;
        default = {};
        example = {"link-name" = pkgs.python3;};
        description = ''
          Links to generate in `/etc/nixos/.sdks` directory.
        '';
      };
    };
  };

  ###### implementation

  config = mkIf cfg.enable {
    environment.etc = mapAttrs' (name: package:
      nameValuePair "${sdksDirectory}/${name}" {source = package;})
    cfg.links;
  };
}
