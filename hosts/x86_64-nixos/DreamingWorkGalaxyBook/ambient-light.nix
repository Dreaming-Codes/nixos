{pkgs, ...}: {
  # iio-sensor-proxy exposes the ISH ambient light sensor over D-Bus.
  hardware.sensor.iio.enable = true;

  # Upstream 90-wluma-backlight.rules; nixpkgs' wluma does not install it.
  # Without it wluma falls back to logind's SetBrightness D-Bus call, one round
  # trip per step, which upstream says is too slow for smooth fades.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="backlight", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/backlight/%k/brightness"
    ACTION=="add", SUBSYSTEM=="leds", RUN+="${pkgs.coreutils}/bin/chgrp video /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
  '';

  home-manager.users.dreamingcodes.services.wluma = {
    enable = true;
    # Nothing else dims the backlight on idle: DMS fades are overlays, and
    # Plasma's "dim screen automatically" must stay off so its writes are not
    # learned as preferences. Fires before the DMS lock at 180 s.
    settings.idle = {
      enabled = true;
      timeout = 120;
      brightness = 30;
    };
  };
}
