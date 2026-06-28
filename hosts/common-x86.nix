{...}: {
  # Enable the Intel/wpa_supplicant enterprise WiFi stack used on the x86 hosts.
  # Asahi (aarch64) hosts use NetworkManager + iwd instead.
  dreaming.networking.wpaSupplicant.enable = true;
  dreaming.networking.intelWifi.enable = true;

  # Gaming stack was historically enabled on every x86 host.
  dreaming.games.enable = true;
}
