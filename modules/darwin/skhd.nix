{
  services.skhd = {
    enable = true;
    skhdConfig = ''
      # niri: Mod+Space -> Terminal (Rio). `open -n` forces a new window/instance
      # instead of just activating the existing one.
      alt - space : open -na Rio

      # niri: Mod+W -> Browser. Chromium opens a fresh window of the running
      # profile with `--new-window` (via `--args`), rather than just focusing.
      alt - w : open -na "Brave Browser" --args --new-window

      # Slack (no niri equivalent; requested binding). Slack is single-instance
      # Electron and has no real multi-window, so this just focuses/launches it.
      alt - s : open -a Slack
    '';
  };
}
