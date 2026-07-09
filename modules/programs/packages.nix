{
  pkgs,
  inputs,
  lib,
  config,
  ...
}: let
  # Use config.nixpkgs.hostPlatform (not pkgs.stdenv) to gate overlays, otherwise
  # referencing pkgs while defining nixpkgs.overlays causes infinite recursion.
  isX86 = config.nixpkgs.hostPlatform.isx86_64;
  cfg = config.dreaming.programs.packages;
  signalDesktop = pkgs.symlinkJoin {
    name = "signal-desktop";
    paths = [pkgs.signal-desktop];
    buildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/signal-desktop \
        --prefix LD_PRELOAD " " "${pkgs.boringssl}/lib/libcrypto.so ${pkgs.boringssl}/lib/libssl.so"
    '';
  };

  rsworktree = pkgs.rustPlatform.buildRustPackage rec {
    pname = "rsworktree";
    version = "0.7.1";

    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-tvgvbOlZvg24WoiC4EPgvqaPizNd/Ir68QQpYjWQZgk=";
    };

    cargoHash = "sha256-PJrl8JghJ69+FbtSVKibiJYFaQQ3PV9+eU7N9nX/TxA=";

    # Tests require git and network access
    doCheck = false;

    nativeBuildInputs = [pkgs.pkg-config];
    buildInputs = [pkgs.openssl];
  };
in {
  options.dreaming.programs.packages.enable =
    lib.mkEnableOption "common system packages and program defaults"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = lib.optionals isX86 [
      (
        final: prev: let
          discordPkgs = import inputs.nixpkgs-discord-vk {
            inherit (prev) system;
            config = prev.config;
          };
        in {
          inherit
            (discordPkgs)
            discord
            discord-canary
            discord-development
            discord-ptb
            ;
        }
      )
    ];

    programs.fish = {
      enable = true;
      generateCompletions = false;
    };

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

    programs.virt-manager.enable = true;

    programs.ydotool.enable = true;

    services = {
      usbmuxd = {
        enable = true;
        package = pkgs.usbmuxd2;
      };
      acpid.enable = true;
      power-profiles-daemon.enable = true;
      mullvad-vpn.enable = true;
      fwupd.enable = true;
    };

    environment.systemPackages = with pkgs;
      [
        wl-clipboard-rs
        wl-clip-persist
        wget
        awscli2
        any-nix-shell
        inputs.nix-alien.packages.${stdenv.hostPlatform.system}.nix-alien
        rio
        adw-gtk3
        kdePackages.qt6ct
        libsForQt5.qt5ct
        gcc
        openssl
        pkg-config
        powertop
        kdePackages.kdialog
        unzip
        # Ark dep
        unrar
        # bottles
        libcamera

        android-tools

        hplipWithPlugin

        uv

        zed-editor
        clang
        clang-tools

        signalDesktop

        libimobiledevice
        ifuse

        claude-code

        socat

        (pantheon.switchboard-with-plugs.override {
          useDefaultPlugs = false;
          plugs = [
            pantheon.switchboard-plug-network
            pantheon.switchboard-plug-sound
            pantheon.switchboard-plug-printers
          ];
        })

        gimp3-with-plugins

        fvm

        lurk
        cartero

        rustscan

        nur.repos.forkprince.helium-nightly
        inputs.brave-origin.legacyPackages.${pkgs.stdenv.hostPlatform.system}.brave

        playerctl
        brightnessctl
        alsa-utils
        libnotify
        termscp

        lldb
        # required to build a lot of rust crates
        protobuf

        # Jupyter Notebook with Rust kernel
        jupyter
        evcxr

        # Git worktree manager from crates.io
        rsworktree
        cargo-edit
        gh

        # Not sure what caused this but now this is needed to make bash work
        bashInteractive

        psst
        (spotify-player.override {
          withAudioBackend = "pulseaudio";
        })
        mission-center

        xwayland-satellite

        mullvad-vpn
        frida-tools

        zig
        (python311.withPackages (
          ps:
            with ps; [
              pyserial
              psutil
            ]
        ))
        node-gyp

        ripgrep
        ripgrep-all
        jq

        nps

        distrobox
        boxbuddy

        typescript-language-server
        jdt-language-server

        pwvucontrol
        crosspipe

        scrcpy

        # kdl formatter
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
        resvg
        sshfs
        xdg-desktop-portal

        uutils-coreutils-noprefix

        # certs for node and other binaries
        cacert

        # Packages moved from home-manager (shared by all users)
        telegram-desktop
        rbw
        btop
        bun
        nodejs
        bintools
        rustup
        kdePackages.kleopatra
        gnupg
        pinentry-qt
        jetbrains-toolbox
        bitwarden-desktop
        just

        # Secrets management
        sops
      ]
      # x86_64-only apps with no native aarch64 build. See docs/asahi-x86-emulation.md
      # for the FEX/muvm plan to run these on Asahi.
      ++ lib.optionals isX86 [
        onlyoffice-desktopeditors
        zoom-us
        slack
        (discord.override {
          withOpenASAR = true;
        })
        spotify
        mullvad-browser
        tor-browser
        saleae-logic-2
      ];

    nixpkgs.config.permittedInsecurePackages = [
      # bitwarden still uses this
      "electron-39.8.10"
    ];

    environment.variables = {
      PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
      # Fix for some app that rely on env to choose audio driver
      SDL_AUDIODRIVER = "pipewire";

      EDITOR = "hx";
      VISUAL = "hx";
      TERMINAL = "rio";
      # Hint Electron apps to use Wayland:
      NIXOS_OZONE_WL = "1";
      GTK_THEME = "adw-gtk3-dark";
      QT_QPA_PLATFORMTHEME = "kde";
      QT_QPA_PLATFORMTHEME_QT6 = "kde";

      # sops-nix: point to age identity for encrypting/decrypting secrets
      SOPS_AGE_KEY_FILE = "/home/dreamingcodes/.nixos/secrets/identity.age";
    };

    environment.sessionVariables = {
      NIX_PACKAGE_SEARCH_EXPERIMENTAL = "true";
    };
  };
}
