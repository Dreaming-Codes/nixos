{
  pkgs,
  inputs,
  lib,
  ...
}: let
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

  programs.virt-manager.enable = true;

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

  environment.systemPackages = with pkgs; [
    wl-clipboard-rs
    wl-clip-persist
    wget
    any-nix-shell
    inputs.nix-alien.packages.${stdenv.hostPlatform.system}.nix-alien
    inputs.opencode.packages.${stdenv.hostPlatform.system}.default
    gcc
    openssl
    pkg-config
    powertop
    kdePackages.kdialog
    unzip
    # Ark dep
    unrar
    bottles
    libcamera

    android-tools

    hplipWithPlugin

    uv

    clang
    clang-tools

    signal-desktop

    libimobiledevice
    ifuse

    google-chrome

    ashell

    socat

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

    nur.repos.forkprince.helium-nightly

    playerctl
    brightnessctl
    alsa-utils
    libnotify
    mixxc
    termscp

    (discord.override {
      withOpenASAR = true;
    })

    lldb
    # required to build a lot of rust crates
    protobuf

    # Jupyter Notebook with Rust kernel
    jupyter
    evcxr

    # Git worktree manager from crates.io
    rsworktree

    # Not sure what caused this but now this is needed to make bash work
    bashInteractive

    upscayl

    psst
    (spotify-player.override {
      withAudioBackend = "pulseaudio";
    })
    spotify
    mission-center

    xwayland-satellite

    mullvad-browser
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

    prismlauncher

    # zed-editor

    ripgrep
    ripgrep-all
    jq

    nps

    distrobox
    boxbuddy

    typescript-language-server

    pwvucontrol
    helvum

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
    bitwarden-desktop
    btop
    bun
    nodejs
    bintools
    rustup
    kdePackages.kleopatra
    gnupg
    kwalletcli
    tor-browser
    jetbrains-toolbox

    # Secrets management
    sops
  ];

  environment.variables = {
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    # Fix for some app that rely on env to choose audio driver
    SDL_AUDIODRIVER = "pipewire";

    EDITOR = "hx";
    VISUAL = "hx";
    # Hint Electron apps to use Wayland:
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORMTHEME = "kde";

    # sops-nix: point to age identity for encrypting/decrypting secrets
    SOPS_AGE_KEY_FILE = "/home/dreamingcodes/.nixos/secrets/identity.age";
  };

  environment.sessionVariables = {
    NIX_PACKAGE_SEARCH_EXPERIMENTAL = "true";
  };
  environment.extraInit = ''
    export LD_LIBRARY_PATH="${
      pkgs.lib.makeLibraryPath [pkgs.openssl]
    }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  '';
}
