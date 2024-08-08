{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;

  cfg = config.custom.misc.sdks;

  # Adjust the directory to use /etc/nixos instead of home directory
  sdksDirectory = "/nixos/.sdks";
in

{

  ###### interface

  options = {

    custom.misc.sdks = {
      enable = mkEnableOption "sdk links";

      links = mkOption {
        type = types.attrs;
        default = { };
        example = { "link-name" = pkgs.python3; };
        description = ''
          Links to generate in `/etc/nixos/.sdks` directory.
        '';
      };
    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    # Adjust the home.file to use environment.etc instead
    environment.etc = mapAttrs'
      (name: package: nameValuePair "${sdksDirectory}/${name}" { source = package; })
      cfg.links;

  };

}
