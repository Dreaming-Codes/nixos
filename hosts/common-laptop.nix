{...}: {
  # Shared laptop power profile: device runtime PM + powerManagement.
  # Imported by every laptop-class host (Blade, WorkDell, Work).
  dreaming.optimization.battery.enable = true;

  # logind ignores the lid for this long after boot/resume (default 30s).
  services.logind.settings.Login.HoldoffTimeoutSec = "10s";
}
