{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.asahi-x86;
  isAarch64Linux = pkgs.stdenv.hostPlatform.system == "aarch64-linux";

  nixpkgsConfig =
    config.nixpkgs.config
    // {
      allowUnfree = true;
      permittedInsecurePackages =
        config.nixpkgs.config.permittedInsecurePackages or [];
    };

  pkgsX86 = import inputs.nixpkgs {
    system = "x86_64-linux";
    config = nixpkgsConfig;
  };

  sommelier = pkgs.sommelier.overrideAttrs (old: {
    doCheck = false;
    mesonCheckPhase = ":";
    nativeBuildInputs =
      old.nativeBuildInputs
      ++ [
        pkgs.gtest
      ];
    postInstall = ''
      rm -f $out/bin/sommelier_test
    '';
    meta =
      old.meta
      // {
        broken = false;
      };
  });

  # A self-contained x86_64 FHS root filesystem for FEX to resolve guest
  # absolute paths (/lib64/ld-linux-x86-64.so.2, /usr/lib, /etc/...) against.
  #
  # This is the critical piece for complex apps like Spotify (Chromium/CEF).
  # muvm composes FEX's RootFS purely from the `-f` EROFS images overlaid
  # against each other; the host aarch64 `/` is NOT in the layer stack. Without
  # a complete x86 base here, FEX has no x86 glibc/loader, fontconfig, NSS or CA
  # bundle, so Chromium-based apps die early in their multiprocess startup.
  #
  # The tree is mostly symlinks into /nix/store, which the guest can follow
  # because the host store is virtiofs-mounted, so the EROFS image stays tiny.
  fhsEnv = pkgsX86.callPackage (inputs.nixpkgs + "/pkgs/build-support/build-fhsenv-chroot/env.nix") {};

  x86FontsConf = pkgsX86.makeFontsConf {
    fontDirectories = [
      pkgsX86.dejavu_fonts
      pkgsX86.liberation_ttf
    ];
  };

  x86BaseFhs = fhsEnv {
    name = "fex-x86-base";
    targetPkgs = p:
      with p; [
        glibc
        gcc.cc.lib
        fontconfig
        freetype
        dejavu_fonts
        liberation_ttf
        cacert
        nss
        nspr
        expat
        zlib
        libdrm
        libglvnd
      ];
    multiPkgs = _: [];
    # The chroot FHS builder points /etc/* at /host/etc/*, which does not exist
    # inside the muvm guest (the host root is mounted at /run/muvm-host). Replace
    # it with a minimal self-contained /etc that Chromium/CEF needs.
    extraBuildCommands = ''
      chmod -R u+w etc || true
      rm -rf etc
      mkdir -p etc/fonts etc/ssl/certs
      ln -s ${x86FontsConf} etc/fonts/fonts.conf
      ln -s ${pkgsX86.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
      ln -s ${pkgsX86.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/cert.pem
      cat > etc/nsswitch.conf <<'NSS'
      passwd:    files
      group:     files
      shadow:    files
      hosts:     files dns
      networks:  files
      services:  files
      protocols: files
      NSS
      cat > etc/passwd <<'PW'
      root:x:0:0:System administrator:/root:/bin/sh
      muvm:x:1000:1000:muvm:/home/muvm:/bin/sh
      nobody:x:65534:65534:Nobody:/:/bin/sh
      PW
      cat > etc/group <<'GRP'
      root:x:0:
      muvm:x:1000:
      nogroup:x:65534:
      GRP
      touch etc/resolv.conf
      cat > etc/hosts <<'HOSTS'
      127.0.0.1 localhost
      ::1 localhost
      HOSTS
    '';
  };

  x86BaseRootfs =
    pkgs.runCommand "muvm-fex-x86-base-rootfs.erofs" {
      nativeBuildInputs = [pkgs.erofs-utils];
    } ''
      mkfs.erofs "$out" ${x86BaseFhs}
    '';

  x86OpenGLRootfs =
    pkgs.runCommand "muvm-fex-x86-opengl-rootfs.erofs" {
      nativeBuildInputs = [pkgs.erofs-utils];
    } ''
      mkdir -p rootfs/run/opengl-driver
      for path in \
        "${pkgsX86.mesa}" \
        "${pkgsX86.libglvnd}" \
        "${pkgsX86.vulkan-loader}"
      do
        cp -R --no-preserve=mode,ownership "$path"/* rootfs/run/opengl-driver/
      done
      mkfs.erofs "$out" rootfs
    '';

  fexGuestInit = pkgs.writeShellApplication {
    name = "muvm-fex-guest-init";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuse
      pkgs.fuse3
      pkgs.util-linux
    ];
    text = ''
      mkdir -p /run/wrappers/bin
      if ! mountpoint -q /run/wrappers; then
        mount -t tmpfs -o exec,suid tmpfs /run/wrappers
        mkdir -p /run/wrappers/bin
      fi
      cp "${lib.getExe' pkgs.fuse "fusermount"}" /run/wrappers/bin/fusermount
      cp "${lib.getExe' pkgs.fuse3 "fusermount3"}" /run/wrappers/bin/fusermount3
      chown root:root /run/wrappers/bin/fusermount /run/wrappers/bin/fusermount3
      chmod u=srx,g=x,o=x /run/wrappers/bin/fusermount /run/wrappers/bin/fusermount3
    '';
  };

  muvmArgs =
    [
      "--emu=fex"
      # Order matters: the first -f image is FEX's base rootfs (full x86 FHS),
      # subsequent images are overlays mounted on top (the GL/Vulkan libs).
      "--fex-image=${x86BaseRootfs}"
      "--fex-image=${x86OpenGLRootfs}"
      "--execute-pre=${lib.getExe fexGuestInit}"
    ]
    ++ lib.concatMap (env: [
      "--env"
      env
    ]) [
      "NIXOS_OZONE_WL=1"
      "GTK_THEME="
      "QT_QPA_PLATFORMTHEME="
      "QT_QPA_PLATFORMTHEME_QT6="
      "XDG_CURRENT_DESKTOP=niri"
    ];

  muvmX86 = pkgs.writeShellApplication {
    name = "muvm-x86";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.socat
    ];
    text = ''
      pids=()
      cleanup() {
        for pid in "''${pids[@]}"; do
          kill "$pid" 2>/dev/null || true
        done
      }
      trap cleanup EXIT INT TERM

      extra_args=()
      ${lib.optionalString cfg.dbusBridge.enable ''
        guest_host="''${ASAHI_X86_DBUS_HOST:-${cfg.dbusBridge.guestHost}}"
        system_port=$(( ${toString cfg.dbusBridge.systemPortBase} + ($$ % 1000) ))
        session_port=$(( ${toString cfg.dbusBridge.sessionPortBase} + ($$ % 1000) ))

        if [[ -S /run/dbus/system_bus_socket ]]; then
          socat \
            "TCP-LISTEN:''${system_port},bind=${cfg.dbusBridge.bindAddress},reuseaddr,fork" \
            "UNIX-CONNECT:/run/dbus/system_bus_socket" &
          pids+=("$!")
          extra_args+=("--env" "DBUS_SYSTEM_BUS_ADDRESS=tcp:host=''${guest_host},port=''${system_port},family=ipv4")
        fi

        if [[ "''${DBUS_SESSION_BUS_ADDRESS:-}" =~ ^unix:path=([^,]+) ]] && [[ -S "''${BASH_REMATCH[1]}" ]]; then
          socat \
            "TCP-LISTEN:''${session_port},bind=${cfg.dbusBridge.bindAddress},reuseaddr,fork" \
            "UNIX-CONNECT:''${BASH_REMATCH[1]}" &
          pids+=("$!")
          extra_args+=("--env" "DBUS_SESSION_BUS_ADDRESS=tcp:host=''${guest_host},port=''${session_port},family=ipv4")
        fi

        if ((''${#pids[@]} > 0)); then
          sleep 0.3
        fi
      ''}

      while IFS='=' read -r env_name _; do
        if [[ "$env_name" == FEX_* ]]; then
          extra_args+=("--env" "$env_name=''${!env_name}")
        fi
      done < <(env)

      while IFS='=' read -r env_name _; do
        case "$env_name" in
          CHROME_*|DISPLAY)
            extra_args+=("--env" "$env_name=''${!env_name}")
            ;;
        esac
      done < <(env)

      ${lib.getExe pkgs.muvm} ${lib.escapeShellArgs muvmArgs} "''${extra_args[@]}" -- "$@"
    '';
  };

  mkMuvmApp = {
    name,
    package,
    executable ? lib.getExe package,
    extraArgs ? [],
    desktopName,
    icon ? name,
    categories ? ["Utility"],
  }: let
    launcher = pkgs.writeShellApplication {
      inherit name;
      text = ''
        exec ${lib.getExe muvmX86} ${lib.escapeShellArg executable} ${lib.escapeShellArgs extraArgs} "$@"
      '';
    };

    desktopItem = pkgs.makeDesktopItem {
      inherit name desktopName icon categories;
      exec = "${name} %U";
      terminal = false;
    };
  in
    pkgs.runCommand "${name}-muvm" {} ''
      mkdir -p "$out/bin" "$out/share"
      ln -s ${lib.getExe launcher} "$out/bin/${name}"

      if [ -d "${package}/share/icons" ]; then
        cp -R --no-preserve=mode,ownership "${package}/share/icons" "$out/share/"
      fi
      if [ -d "${package}/share/pixmaps" ]; then
        cp -R --no-preserve=mode,ownership "${package}/share/pixmaps" "$out/share/"
      fi

       cp -R --no-preserve=mode,ownership "${desktopItem}/share/applications" "$out/share/"
    '';

  x86Apps = [];
in {
  options.programs.asahi-x86.enable = lib.mkEnableOption "x86_64 Linux application support through muvm and FEX on Asahi";
  options.programs.asahi-x86.dockerCompat = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Register x86_64 binfmt support for Docker linux/amd64 images. This does not provide a 4K-page kernel to containers.";
  };
  options.programs.asahi-x86.dbusBridge = {
    enable = lib.mkEnableOption "host D-Bus bridge for x86 apps running inside muvm" // {default = true;};
    guestHost = lib.mkOption {
      type = lib.types.str;
      default = "10.0.2.2";
      description = "Host address as seen from the muvm guest through passt.";
    };
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Host address for local D-Bus TCP bridge listeners.";
    };
    systemPortBase = lib.mkOption {
      type = lib.types.port;
      default = 15500;
      description = "Base TCP port for the bridged host system bus.";
    };
    sessionPortBase = lib.mkOption {
      type = lib.types.port;
      default = 16500;
      description = "Base TCP port for the bridged host session bus.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isAarch64Linux;
        message = "programs.asahi-x86 is only supported on aarch64-linux hosts.";
      }
    ];

    hardware.graphics.enable = true;

    boot.binfmt.emulatedSystems = lib.mkIf cfg.dockerCompat [
      "x86_64-linux"
    ];

    environment.systemPackages =
      [
        pkgs.fex
        pkgs.muvm
        sommelier
        muvmX86
      ]
      ++ x86Apps;
  };
}
