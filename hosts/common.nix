{
  config,
  pkgs,
  inputs,
  ...
}: {
  nixpkgs.overlays = [inputs.nix-cachyos-kernel.overlays.default];

  imports =
    [
      ../modules/core/boot.nix
      ../modules/core/networking.nix
      ../modules/core/nix.nix
      ../modules/core/security.nix
      ../modules/hardware/audio.nix
      ../modules/hardware/graphics.nix
      ../modules/hardware/optimization.nix
      ../modules/desktop/hyprland.nix
      ../modules/desktop/fonts.nix
      ../modules/desktop/xdg.nix
      ../modules/services/docker.nix
      ../modules/services/printing.nix
      ../modules/services/samba.nix
      ../modules/services/auto-update.nix
      ../modules/programs/steam.nix
      ../modules/programs/development.nix
      ../modules/programs/packages.nix
      ../modules/users/dreamingcodes.nix
    ]
    ++ (
      if builtins.pathExists /etc/nixos/secrets/github.nix
      then [/etc/nixos/secrets/github.nix]
      else []
    );

  # Timezone and locale (common to all hosts)
  services.automatic-timezoned.enable = true;
  i18n.defaultLocale = "en_US.UTF-8";

  # Use Cloudflare-based geolocation service
  services.geoclue2 = {
    enable = true;
    geoProviderUrl = "https://cloudflare-location-service.dreamingcodes.workers.dev/";
  };

  # Ensure geoclue starts after wpa_supplicant to reduce WiFi scan race condition
  systemd.services.geoclue.after = ["wpa_supplicant.service"];
  systemd.services.geoclue.wants = ["wpa_supplicant.service"];

  # State version
  system.stateVersion = "24.11";

  # Disable NixOS options documentation to avoid builtins.toFile warnings from NUR
  documentation.nixos.enable = false;
}
