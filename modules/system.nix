{
  pkgs,
  pkgsStable,
  dolphin-overlay,
  inputs,
  self,
  ...
}: {
  boot.loader.limine.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  imports = [
    inputs.gauntlet.nixosModules.default
  ];

  security.pki.certificateFiles = [
    ./AdGuard_CLI_CA.pem
  ];

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.UPower.PowerProfiles.switch-profile" &&
        subject.isInGroup("wheel")
      ) {
        return polkit.Result.YES;
      }
    });
    polkit.addRule(function(action, subject) {
      if (subject.isInGroup("wheel"))
        return polkit.Result.YES;
    });
  '';

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

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

  # nixpkgs.overlays = [dolphin-overlay.overlays.default];
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

  programs.weylus = {
    enable = true;
    openFirewall = true;
  };

  environment.systemPackages = with pkgs; [
    wl-clipboard-rs
    wget
    any-nix-shell
    inputs.nix-alien.packages.${stdenv.hostPlatform.system}.nix-alien
    gcc
    openssl
    pkg-config
    powertop
    kdePackages.kdialog
    unzip
    # Ark dep
    unrar
    bottles
    # yaak
    libcamera

    impala
    hplipWithPlugin

    # orca-slicer

    uv

    clang
    clang-tools

    freerdp

    signal-desktop

    libimobiledevice
    ifuse

    google-chrome

    ashell

    (pantheon.switchboard-with-plugs.override {
      useDefaultPlugs = false;
      plugs = [
        pantheon.switchboard-plug-network
        pantheon.switchboard-plug-sound
        pantheon.switchboard-plug-printers
        pantheon.switchboard-plug-bluetooth
      ];
    })

    gimp3-with-plugins

    fvm
    obsidian

    # required for obsidian cpp code run to work
    cling

    lurk
    cartero

    rustscan

    # (callPackage ./davinci-resolve.nix {
    #   studioVariant = true;
    # })
    #
    nur.repos.forkprince.helium-nightly

    # clipcat
    playerctl
    brightnessctl
    alsa-utils
    libnotify
    mixxc
    termscp

    (discord.override {
      withOpenASAR = true;
      # withMoonlight = true;
      # withVencord = true;
    })

    lldb
    # required to build a lot of rust ctates
    protobuf

    # Not sure what caused this but now this is needed to make bash work
    bashInteractive

    upscayl

    psst
    (spotify-player.override {
      withAudioBackend = "pulseaudio";
    })
    mission-center

    xwayland-satellite

    mullvad-browser
    mullvad-vpn
    frida-tools

    # Java
    # zulu23
    # kotlin

    zig
    (python311.withPackages (
      ps:
        with ps; [
          pyserial
          psutil
        ]
    ))
    node-gyp

    prismlauncher

    zed-editor

    distrobox
    boxbuddy

    # jdt-language-server
    # kotlin-language-server
    typescript-language-server
    # dprint

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

    # better diffs
    difftastic

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
      xdg-desktop-portal-hyprland
      # Add xdg-desktop-portal-gtk for Wayland GTK apps (font issues etc.)
      xdg-desktop-portal-gtk
      kdePackages.xdg-desktop-portal-kde
    ];
  };

  # Allow GTK applications to show an appmenu on KDE
  # Broken: 11/03/2025
  # chaotic.appmenu-gtk3-module.enable = true;

  custom.misc.sdks = {
    enable = true;
    links = {
      nodejs = pkgs.nodejs;
      jdk = pkgs.temurin-bin;
      # kotlin = pkgs.kotlin;
      jdk17 = pkgs.temurin-bin-17;
      # jdk23 = pkgs.zulu23;
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
