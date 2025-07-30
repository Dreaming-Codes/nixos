{
  pkgs,
  pkgsStable,
  pkgsDreamingCodes,
  dolphin-overlay,
  rip2,
  somo,
  zed,
  inputs,
  self,
  ...
}: {
  boot.loader.limine.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services = {
    udev = {
      extraRules = ''
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1915", ATTRS{idProduct}=="522a", ATTRS{serial}=="84014353616C81E9", GROUP="wireshark", MODE="0666"
      '';
    };
  };

  imports = [
    inputs.gauntlet.nixosModules.default
  ];

  security.pki.certificateFiles = [
    ./AdGuard_CLI_CA.pem
  ];

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

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  security.sudo-rs.enable = true;
  security.sudo-rs.wheelNeedsPassword = false;
  security.pam.services.login.enableKwallet = true;
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "10000";
    }
  ];

  # Disable man page cache generation since it's very slow and fish enable it by default
  documentation.man.generateCaches = false;

  hardware.bluetooth.enable = true;

  services = {
    usbmuxd = {
      enable = true;
      package = pkgs.usbmuxd2;
    };
    acpid.enable = true;
    power-profiles-daemon.enable = true;
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        userServices = true;
      };
    };
  };

  programs.virt-manager.enable = true;

  fonts.packages = with pkgs; [nerd-fonts.fira-code];

  nixpkgs.overlays = [dolphin-overlay.overlays.default];
  systemd.user.services.gpu-screen-recorder.wantedBy = ["default.target"];
  systemd.user.services.gpu-screen-recorder-ui.wantedBy = ["default.target"];

  programs.fish.enable = true;

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  environment.systemPackages = with pkgs; [
    wl-clipboard-rs
    wget
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
    bottles
    yaak
    libcamera

    signal-desktop

    libimobiledevice
    ifuse

    google-chrome

    gimp3-with-plugins

    godot

    lurk
    cartero

    rustscan

    # (callPackage ./davinci-resolve.nix {
    #   studioVariant = true;
    # })

    clipcat
    playerctl
    brightnessctl
    alsa-utils
    libnotify
    mixxc
    termscp

    (discord.override {
      withOpenASAR = true;
      withMoonlight = true;
      # withVencord = true;
    })

    lldb

    # Not sure what caused this but now this is needed to make bash work
    bashInteractive

    upscayl
    stremio

    psst
    spotify-player
    mission-center

    xwayland-satellite

    mullvad-browser
    mullvad-vpn
    pkgsStable.frida-tools

    # needed for browser widget
    kdePackages.qtwebengine

    # Java
    zulu23
    kotlin

    zig
    python313
    python313Packages.pyserial
    node-gyp

    prismlauncher

    pkgsDreamingCodes.expo-orbit

    rip2.packages.${system}.default
    somo.packages.${system}.default
    zed.packages.${system}.default

    distrobox
    boxbuddy

    jdt-language-server
    kotlin-language-server
    typescript-language-server
    dprint

    pwvucontrol
    helvum

    scrcpy

    #kdl formatter
    kdlfmt
    # Nix LSP
    nil
    # Nix fmt
    alejandra

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

    uutils-coreutils-noprefix
  ];

  xdg.portal = {
    xdgOpenUsePortal = true;
    enable = true;

    config = {
      hyprland = {
        default = ["hyprland" "gtk" "kde"];
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
      };
    };

    extraPortals = with pkgs; [
      inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland
      # Add xdg-desktop-portal-gtk for Wayland GTK apps (font issues etc.)
      xdg-desktop-portal-gtk
      kdePackages.xdg-desktop-portal-kde
    ];
  };

  # Allow GTK applications to show an appmenu on KDE
  chaotic.appmenu-gtk3-module.enable = true;

  custom.misc.sdks = {
    enable = true;
    links = {
      nodejs = pkgs.nodejs;
      jdk = pkgs.temurin-bin;
      kotlin = pkgs.kotlin;
      jdk17 = pkgs.temurin-bin-17;
      jdk23 = pkgs.zulu23;
    };
  };

  environment.variables = {
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    # Fix for some app that rely on env to choose audio driver
    SDL_AUDIODRIVER = "pipewire";

    EDITOR = "hx";
    VISUAL = "hx";
    # Hint Electron apps to use Wayland:
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "kde";
  };

  services.mullvad-vpn.enable = true;

  services.fwupd.enable = true;

  system.stateVersion = "24.11";
}
