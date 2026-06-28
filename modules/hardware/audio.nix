{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.hardware.audio;
in {
  options.dreaming.hardware.audio.enable =
    lib.mkEnableOption "audio stack (pipewire/wireplumber)"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    services.pulseaudio.enable = false;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      systemWide = false;
      wireplumber.enable = true;
    };
  };
}
