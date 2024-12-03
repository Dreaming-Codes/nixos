{ config, pkgs, pkgsStable, inputs, chaotic, ... }: {
  zramSwap.enable = true;

  programs.nh = { flake = "/home/dreamingcodes/.nixos/"; };

  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features =
    [ "nix-command" "flakes" "dynamic-derivations" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "it_IT.UTF-8";
    LC_IDENTIFICATION = "it_IT.UTF-8";
    LC_MEASUREMENT = "it_IT.UTF-8";
    LC_MONETARY = "it_IT.UTF-8";
    LC_NAME = "it_IT.UTF-8";
    LC_NUMERIC = "it_IT.UTF-8";
    LC_PAPER = "it_IT.UTF-8";
    LC_TELEPHONE = "it_IT.UTF-8";
    LC_TIME = "it_IT.UTF-8";
  };

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  security.sudo.wheelNeedsPassword = false;
  security.pam.services.login.enableKwallet = true;

  # Disable man page cache generation since it's very slow and fish enable it by default
  documentation.man.generateCaches = false;

  nixpkgs.config.allowUnfree = true;
  hardware.bluetooth.enable = true;

  programs.virt-manager.enable = true;

  fonts.packages = with pkgs; [
    fira-code-nerdfont
  ];

  environment.systemPackages = with pkgs; [
    wl-clipboard-rs
    wget
    inputs.kwin-effects-forceblur.packages.${pkgs.system}.default
    any-nix-shell
    inputs.nix-alien.packages.${system}.nix-alien
    gcc
    openssl
    pkg-config
    powertop
    kdePackages.kdialog
    unzip
    # Ark dep
    unrar
    looking-glass-client
    bottles
    appimage-run

    mullvad-browser
    mullvad-vpn

    pkgsStable.frida-tools

    # needed for browser widget
    kdePackages.qtwebengine

    # Java
    zulu23

    # Zed
    zed-editor_git

    distrobox
    boxbuddy

    # Nix LSP
    nil
    # Nix fmt
    nixfmt-classic

    ffmpeg
    mpv

    # From https://gitlab.com/garuda-linux/garuda-nix-subsystem/-/blob/main/internal/modules/dr460nized/apps.nix?ref_type=heads
    ffmpegthumbnailer
    kdePackages.kdegraphics-thumbnailers
    kdePackages.kimageformats
    kdePackages.kio-admin
    libinput-gestures
    plasma-plugin-blurredwallpaper
    resvg
    sshfs
    xdg-desktop-portal
  ];

  # Add xdg-desktop-portal-gtk for Wayland GTK apps (font issues etc.)
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # Allow GTK applications to show an appmenu on KDE
  chaotic.appmenu-gtk3-module.enable = true;

  custom.misc.sdks = {
    enable = true;
    links = {
      nodejs = pkgs.nodejs;
      jdk = pkgs.temurin-bin;
      jdk17 = pkgs.temurin-bin-17;
    };
  };

  environment.variables = {
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    # Fix for some app that rely on env to choose audio driver
    SDL_AUDIODRIVER = "pipewire";
  };

  services.mullvad-vpn.enable = true;

  services.fwupd.enable = true;

  system.stateVersion = "24.11";
}
