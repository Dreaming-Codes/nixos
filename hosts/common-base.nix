{
  pkgs,
  config,
  lib,
  ...
}: {
  # All feature modules are imported for every nixos host via easy-hosts
  # (flake-modules/hosts.nix, perClass "nixos"). This file only selects features
  # via dreaming.* toggles and sets the few unconditional shared settings.

  # Timezone and locale (common to all hosts)
  services.automatic-timezoned.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";

  # Use Cloudflare-based geolocation service
  services.geoclue2 = {
    enable = true;
    geoProviderUrl = "https://cloudflare-location-service.dreamingcodes.workers.dev/";
  };

  services.espanso = {
    enable = true;
    package = pkgs.espanso-wayland;
  };

  dreaming.optimization.enable = true;

  dreaming.nixFileOverlay = {
    enable = true;
    systemRepoPath = "/home/dreamingcodes/.nixos";
    users = ["dreamingcodes"];
  };

  # Ensure geoclue starts after wpa_supplicant to reduce WiFi scan race condition.
  # Only applies when wpa_supplicant is the NetworkManager backend (iwd-based hosts
  # like the Asahi work laptop have no such unit).
  systemd.services.geoclue = lib.mkIf (config.networking.networkmanager.wifi.backend != "iwd") {
    after = ["wpa_supplicant.service"];
    wants = ["wpa_supplicant.service"];
  };

  # State version
  system.stateVersion = "26.05";

  # Disable NixOS options documentation to avoid builtins.toFile warnings from NUR
  documentation.nixos.enable = false;
  documentation.doc.enable = false;
}
