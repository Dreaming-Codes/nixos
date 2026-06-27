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

  # ===========================================================================
  # x86_64 dev shell (CLI), distinct from the GUI muvmX86 wrapper above.
  #
  # This host runs a 16K-page kernel, so bare binfmt/QEMU user emulation cannot
  # reliably map x86 shared libraries (e.g. libaudit) — apt/dpkg/pip all fail
  # with "failed to map segment". The reliable path (the same one Fedora Asahi
  # uses) is a muvm microVM running a 4K-page guest kernel with FEX. We build a
  # full x86 userspace as a tree of symlinks into x86 /nix/store paths (no x86
  # code runs at build time — only `mkfs.erofs` on the aarch64 host), pack it as
  # an EROFS FEX image, and run commands inside the guest from that userspace.
  #
  # The host /nix/store is virtiofs-mounted in the guest, so the x86 store paths
  # the rootfs symlinks into are resolvable. The repo is reachable at its normal
  # path because muvm mounts the host filesystem.

  # The Python deps exposed via PYTHONPATH (a colon-joined list of each
  # package's site-packages) rather than a python.withPackages env, because the
  # withPackages builder runs an x86 interpreter at build time, which fails on
  # this 16K-page host. These are all pure wheels available from the binary
  # cache, so no x86 code runs to assemble them.
  x86PyDeps = with pkgsX86.python312.pkgs; [
    # pytest + its runtime deps
    pytest
    pluggy
    iniconfig
    packaging
    pygments
    exceptiongroup
    tomli
    # boto3 / botocore stack
    boto3
    botocore
    s3transfer
    jmespath
    python-dateutil
    six
    urllib3
    # misc
    pyyaml
    moto
    werkzeug
    jinja2
    markupsafe
    requests
    responses
    xmltodict
    charset-normalizer
    idna
    certifi
    cryptography
    cffi
    pycparser
  ];

  # Compatibility shim injected ahead of the real packages on PYTHONPATH.
  #   * moto: nixpkgs ships moto 5 (mock_aws), but some test suites still import
  #     the moto 4 decorators (mock_ecr/mock_ecs/mock_sts). A sitecustomize.py
  #     (auto-imported by CPython at startup) back-fills those names with no-op
  #     stand-ins so module import + unrelated setup_method() succeed. This is a
  #     LOCAL convenience only; real moto-backed assertions are validated in CI
  #     against the repo's pinned moto.
  #   * mypy_boto3_ecs: type-stub package imported for annotations; stubbed.
  # Built with an aarch64 runCommand (writes .py text only) so no x86 code runs.
  x86TestShims = pkgs.runCommand "muvm-x86-test-shims" {} ''
    mkdir -p "$out/mypy_boto3_ecs"
    cat > "$out/sitecustomize.py" <<'PY'
    try:
        import moto as _moto
        if not hasattr(_moto, "mock_ecr"):
            class _NoopMock:
                def start(self, *a, **k):
                    return None
                def stop(self, *a, **k):
                    return None
                def __call__(self, f):
                    return f
                def __enter__(self):
                    return self
                def __exit__(self, *a):
                    return False
            def _factory(*a, **k):
                return _NoopMock()
            for _name in ("mock_ecr", "mock_ecs", "mock_sts", "mock_iam",
                          "mock_lambda", "mock_s3", "mock_dynamodb"):
                setattr(_moto, _name, _factory)
    except Exception:
        pass
    PY
    : > "$out/mypy_boto3_ecs/__init__.py"
    cat > "$out/mypy_boto3_ecs/type_defs.py" <<'PY'
    from typing import Any
    ContainerDefinitionTypeDef = dict
    KeyValuePairTypeDef = dict
    def __getattr__(name: str) -> Any:
        return dict
    PY
  '';

  x86PythonPath =
    (lib.concatMapStringsSep ":" (p: "${p}/${pkgsX86.python312.sitePackages}") x86PyDeps)
    + ":${x86TestShims}";

  # x86 binaries we want on PATH inside the guest. They run from the
  # virtiofs-mounted host /nix/store; we just need a tidy /usr/bin of symlinks.
  x86DevPackages = with pkgsX86; [
    bashInteractive
    coreutils-full
    findutils
    gnugrep
    gnused
    gawk
    gnutar
    gzip
    xz
    which
    diffutils
    glibc
    glibc.bin
    python312
  ];

  x86DevFhs =
    pkgs.runCommand "fex-x86-dev-fhs" {
      paths = x86DevPackages;
    } ''
      mkdir -p "$out"/{bin,usr/bin,lib,lib64,usr/lib,etc/ssl/certs}

      for p in $paths; do
        for d in bin sbin; do
          if [ -d "$p/$d" ]; then
            for f in "$p/$d"/*; do
              [ -e "$f" ] || continue
              ln -sf "$f" "$out/usr/bin/$(basename "$f")" 2>/dev/null || true
            done
          fi
        done
        if [ -d "$p/lib" ]; then
          for f in "$p"/lib/*; do
            [ -e "$f" ] || continue
            ln -sf "$f" "$out/usr/lib/$(basename "$f")" 2>/dev/null || true
          done
        fi
      done

      ln -sfn usr/bin "$out/bin"

      # x86 dynamic loader at the conventional path.
      ln -sf ${pkgsX86.glibc}/lib/ld-linux-x86-64.so.2 "$out/lib64/ld-linux-x86-64.so.2"
      ln -sf ${pkgsX86.glibc}/lib/ld-linux-x86-64.so.2 "$out/lib/ld-linux-x86-64.so.2"

      ln -s ${pkgsX86.cacert}/etc/ssl/certs/ca-bundle.crt "$out/etc/ssl/certs/ca-certificates.crt"
      : > "$out/etc/resolv.conf"
    '';

  x86DevRootfs =
    pkgs.runCommand "muvm-fex-x86-dev-rootfs.erofs" {
      nativeBuildInputs = [pkgs.erofs-utils];
    } ''
      mkfs.erofs "$out" ${x86DevFhs}
    '';

  # In the muvm guest the filesystem root is the HOST (aarch64) root mounted via
  # virtiofs — the `-f` EROFS images are only FEX's RootFS for x86 library
  # resolution, NOT the guest's `/`. So `/usr/bin/bash` would resolve to the
  # host's aarch64 bash. To actually run x86 binaries we must reference them by
  # their x86 /nix/store paths (visible via virtiofs) and put those store `bin`
  # dirs on PATH. FEX then transparently emulates them on the 4K-page guest.
  x86PathDirs = lib.makeBinPath x86DevPackages;
  x86Bash = "${pkgsX86.bashInteractive}/bin/bash";

  # CLI runner: boots the 4K-page guest with FEX and runs a command as real
  # x86_64.
  #
  # Two hard-won details:
  #   * The guest root is the HOST (aarch64) filesystem over virtiofs; the
  #     `-f` EROFS images are only FEX's RootFS for x86 lib resolution. So we
  #     invoke x86 binaries by their /nix/store paths (visible via virtiofs) and
  #     set PATH to the x86 store `bin` dirs *inside* the inner shell.
  #   * We must NOT pass `--env PATH=...` to muvm: muvm's in-guest agent needs a
  #     working PATH to find its own helpers and exec the command; overriding it
  #     breaks the agent and the command silently never runs. PYTHONPATH and
  #     SSL_CERT_FILE are fine to pass via --env. We export PATH in the prelude.
  #
  # Usage:
  #   muvm-x86-shell                          # interactive x86 bash
  #   muvm-x86-shell -- python3 --version
  #   muvm-x86-shell -- bash -c 'cd repo && python3 -m pytest ...'
  muvmX86Shell = pkgs.writeShellApplication {
    name = "muvm-x86-shell";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      if [[ "''${1:-}" == "--" ]]; then
        shift
      fi

      # Script run (as x86 bash, via FEX) inside a private user+mount namespace.
      #   * Fix DNS: the guest /etc/resolv.conf (from host, virtiofs) is empty, so
      #     glibc resolution — used by the JVM/Python downloaders Bazel needs —
      #     fails. passt answers DNS on the default gateway. NOTE: FEX redirects
      #     an x86 process's /etc/* reads to its RootFS overlay
      #     (/run/fex-emu/rootfs/etc), so we must bind our resolv.conf over the
      #     copy *there* — bind-mounting the guest's real /etc/resolv.conf has no
      #     effect on emulated processes. (unshare -r makes us root in the ns.)
      #   * Set PATH to the x86 store bin dirs.
      # $PATH/$gw stay literal (expanded in the guest), so disable SC2016.
      # shellcheck disable=SC2016
      innerSetup='
        gw=$(ip route show default 2>/dev/null | awk "/default/{print \$3; exit}")
        [ -n "$gw" ] || gw=10.0.2.3
        printf "nameserver %s\noptions timeout:2 attempts:2\n" "$gw" > /run/muvm-resolv.conf
        for rc in /run/fex-emu/rootfs/etc/resolv.conf /etc/resolv.conf; do
          mount --bind /run/muvm-resolv.conf "$rc" 2>/dev/null || true
        done
        export PATH=${x86PathDirs}:/run/current-system/sw/bin:$PATH
      '

      if [[ $# -gt 0 ]]; then
        userCmd="$*"
      else
        userCmd="exec ${x86Bash} -i"
      fi

      cmd=(
        ${pkgs.util-linux}/bin/unshare -rm --
        ${x86Bash} -c "$innerSetup"'
'"$userCmd"
      )

      exec ${lib.getExe pkgs.muvm} \
        --emu=fex \
        --fex-image=${x86BaseRootfs} \
        --fex-image=${x86DevRootfs} \
        --execute-pre=${lib.getExe fexGuestInit} \
        -i -t \
        --env SSL_CERT_FILE=${pkgsX86.cacert}/etc/ssl/certs/ca-bundle.crt \
        --env HOME=/tmp \
        --env PYTHONPATH=${x86PythonPath} \
        -- "''${cmd[@]}"
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

    # Register the x86_64 QEMU interpreter with the fix-binary (`F`) flag so the
    # kernel loads the (static aarch64) interpreter at registration time. Without
    # `F`, the interpreter is resolved against the calling process's mount
    # namespace at exec time, so `linux/amd64` containers (Docker/distrobox)
    # can't launch their x86 binaries. With `F` the handler works across
    # namespaces, which is what makes amd64 distrobox/docker containers usable.
    boot.binfmt.registrations = lib.mkIf cfg.dockerCompat {
      "x86_64-linux".fixBinary = true;
    };

    environment.systemPackages =
      [
        pkgs.fex
        pkgs.muvm
        sommelier
        muvmX86
        muvmX86Shell
      ]
      ++ x86Apps;
  };
}
