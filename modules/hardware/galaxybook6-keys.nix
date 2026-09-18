{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.hardware.galaxybook6-keys;
in {
  options.dreaming.hardware.galaxybook6-keys = {
    enable = lib.mkEnableOption ''
      Galaxy Book6 Ultra keyboard fix: Copilot key remapped to Meta via keyd.
      Firmware emits leftmeta+leftshift+f23 for that key.
    '';
  };

  config = lib.mkIf cfg.enable {
    services.keyd.enable = true;
    services.keyd.keyboards.galaxybook = {
      # AT Translated Set 2 keyboard (i8042)
      ids = ["0001:0001:09650417"];
      settings.main = {
        "leftmeta+leftshift+f23" = "rightmeta";
      };
    };
  };
}
