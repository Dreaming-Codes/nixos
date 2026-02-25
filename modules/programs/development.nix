{
  pkgs,
  config,
  lib,
  ...
}: let
  inherit (lib) mapAttrs' mkEnableOption mkIf mkOption nameValuePair types;

  cfg = config.custom.misc.sdks;
  sdksDirectory = "/nixos/.sdks";
in {
  ###### interface

  options = {
    custom.misc.sdks = {
      enable = mkEnableOption "sdk links";

      links = mkOption {
        type = types.attrs;
        default = {};
        example = {"link-name" = pkgs.python3;};
        description = ''
          Links to generate in `/etc/nixos/.sdks` directory.
        '';
      };
    };
  };

  ###### implementation

  config = {
    # SDK links implementation
    environment.etc = mkIf cfg.enable (mapAttrs' (name: package:
      nameValuePair "${sdksDirectory}/${name}" {source = package;})
    cfg.links);

    # SDK configuration
    custom.misc.sdks = {
      enable = true;
      links = {
        nodejs = pkgs.nodejs;
        jdk = pkgs.temurin-bin;
        jdk17 = pkgs.temurin-bin-17;
      };
    };

    # Partition-manager does not work if not installed globally
    programs.partition-manager.enable = true;
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      SDL
      SDL2
      SDL2_image
      SDL2_mixer
      SDL2_ttf
      SDL_image
      SDL_mixer
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      bzip2
      cairo
      cups
      curlWithGnuTls
      dbus
      dbus-glib
      desktop-file-utils
      e2fsprogs
      expat
      flac
      fontconfig
      freeglut
      freetype
      fribidi
      fuse
      fuse3
      gdk-pixbuf
      glew_1_10
      glib
      libgcc
      gcc
      libepoxy
      gmp
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-ugly
      gst_all_1.gstreamer
      gtk2
      gtk3
      harfbuzz
      icu
      keyutils.lib
      libGL
      libGLU
      libappindicator-gtk2
      libcaca
      libcanberra
      libcap
      libclang.lib
      libdbusmenu
      libdrm
      libgcrypt
      libgpg-error
      libidn
      libjack2
      libjpeg
      libmikmod
      libogg
      libpng
      libgbm
      libpng12
      libpulseaudio
      librsvg
      libsamplerate
      libthai
      libtheora
      libtiff
      libudev0-shim
      libusb1
      libuuid
      libvdpau
      libvorbis
      libvpx
      libxcrypt-legacy
      libxkbcommon
      libxml2
      mesa
      nspr
      nss
      openssl
      p11-kit
      pango
      pixman
      python3
      speex
      stdenv.cc.cc
      tbb
      udev
      vulkan-loader
      wayland
      libICE
      libSM
      libX11
      libXScrnSaver
      libXcomposite
      libXcursor
      libXdamage
      libXext
      libXfixes
      libXft
      libXi
      libXinerama
      libXmu
      libXrandr
      libXrender
      libXt
      libXtst
      libXxf86vm
      libpciaccess
      libxcb
      xcbutil
      xcbutilimage
      xcbutilkeysyms
      xcbutilrenderutil
      xcbutilwm
      xkeyboardconfig
      libxkbfile
      libbsd
      xz
      zlib
    ];
  };
}
