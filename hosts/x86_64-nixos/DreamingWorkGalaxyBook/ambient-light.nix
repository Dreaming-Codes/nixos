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
    settings = {
      # Galaxy Book6 Ultra ISH ALS at iio:device0 (name=als).
      als.iio = {
        path = "/sys/bus/iio/devices";
        thresholds = {
          "0" = "night";
          "20" = "dark";
          "80" = "dim";
          "250" = "normal";
          "500" = "bright";
          "800" = "outdoors";
        };
      };

      output.backlight = [
        {
          name = "eDP-1";
          path = "/sys/class/backlight/intel_backlight";
          capturer = "wayland";
        }
      ];
    };
  };
}
