{
  pkgs,
  config,
  lib,
  ...
}: let
  inherit
    (lib)
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;

  cfg = config.dreaming.programs.development;
  sdksDirectory = "/nixos/.sdks";
in {
  ###### interface

  options.dreaming.programs.development = {
    enable =
      mkEnableOption "development tooling (SDK links, nix-ld, partition-manager)"
      // {
        default = true;
      };

    sdks.links = mkOption {
      type = types.attrs;
      default = {};
      example = {
        "link-name" = pkgs.python3;
      };
      description = ''
        Links to generate in `/etc/nixos/.sdks` directory.
      '';
    };
  };

  ###### implementation

  config = mkIf cfg.enable {
    # SDK links implementation
    environment.etc =
      mapAttrs' (
        name: package: nameValuePair "${sdksDirectory}/${name}" {source = package;}
      )
      cfg.sdks.links;

    # SDK configuration
    dreaming.programs.development.sdks.links = {
      nodejs = pkgs.nodejs;
      jdk = pkgs.temurin-bin;
      jdk17 = pkgs.temurin-bin-17;
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
      ocl-icd
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
