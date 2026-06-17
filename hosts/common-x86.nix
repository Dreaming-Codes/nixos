{...}: {
  imports = [
    ../modules/core/boot.nix
    ../modules/hardware/graphics.nix
    ../modules/programs/steam.nix
  ];

  # Enable the Intel/wpa_supplicant enterprise WiFi stack used on the x86 hosts.
  # Asahi (aarch64) hosts use NetworkManager + iwd instead.
  custom.networking.wpaSupplicant.enable = true;
  custom.networking.intelWifi.enable = true;
}
