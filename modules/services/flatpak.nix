{pkgs, ...}: {
  # Flatpak + Discover integration (desktop only)
  services.flatpak.enable = true;
  services.packagekit.enable = true;

  # Flatpak auto-update (system-wide)
  systemd.services.flatpak-update = {
    description = "Update Flatpak packages (system)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.flatpak}/bin/flatpak update -y";
    };
  };

  # Flatpak auto-update (user)
  systemd.user.services.flatpak-update-user = {
    description = "Update Flatpak packages (user)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.flatpak}/bin/flatpak update -y --user";
    };
  };

  systemd.user.timers.flatpak-update-user = {
    description = "Auto-update Flatpak packages (user)";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  systemd.timers.flatpak-update = {
    description = "Auto-update Flatpak packages";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
