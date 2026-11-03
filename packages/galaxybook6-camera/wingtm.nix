{
  stdenv,
  fetchurl,
  unzip,
  pkgsCross,
  wineWowPackages,
  hal,
}: let
  mingw = pkgsCross.mingwW64;
  mcf = mingw.windows.mcfgthreads;
  inc = "${hal.bins}/include/ipu75xa/ia_imaging";
  wine = wineWowPackages.stable;

  # Samsung's camera driver, as in ipu7-hal.nix; the MFT carries the Windows CCA.
  windowsDriver = fetchurl {
    url = "https://downloadcenter.samsung.com/content/DR/202608/20260811081131834/BASW-A4296A0R_1063.ZIP";
    hash = "sha256-mZnTw8woT12RXuDnrfZWvqAA4YdY7NIU6Uk8w/tPqNY=";
  };
in
  # The Windows CCA's GBCE tone map for the Linux HAL: libwingtm.so (LD_PRELOAD in the HAL
  # process) mirrors the HAL's CCA calls to wingtm.exe, the Windows CCA under Wine.
  stdenv.mkDerivation {
    pname = "wingtm";
    version = "0.1";

    passthru = {inherit wine;};

    src = ./wingtm;

    nativeBuildInputs = [unzip mingw.stdenv.cc];

    buildPhase = ''
      runHook preBuild
      S=${hal.src}
      D=$S/modules/ipu_desc/ipu75xa
      $CXX -std=c++17 -O1 -w -DSTATIC_GRAPH_USE_IA_AIC_TYPES -DPAC_ENABLE -DIPU_SYSVER_ipu75 \
        -DGRC_IPU75XA -DHAVE_LINUX_OS -I$D -I$S/modules/ipu_desc -I$S/include -I$S/include/api \
        -I$S/include/utils -I$S/src -I${inc} -o aiccfg aiccfg.cpp $D/CBLayoutUtils.cpp \
        $D/Ipu75xaTerminalDescriptorAutogen.cpp $D/Ipu75xaStaticGraphAutogen.cpp \
        $D/Ipu75xaStaticGraphReaderAutogen.cpp
      ./aiccfg ${hal}/etc/camera/ipu75xa/gcss/SC200PC_KAFC917.IPU75XA.bin sc200pc_1080p.aiccfg
      $CXX -std=c++17 -O2 -fPIC -shared -w -DPAC_ENABLE -DIPU_SYSVER_ipu75 -I. -I${inc} \
        -o libwingtm.so shim.cpp -ldl -lpthread
      x86_64-w64-mingw32-g++ -std=c++17 -O1 -w -DPAC_ENABLE -DIPU_SYSVER_ipu75 -I. -I${inc} \
        -I${mcf.dev}/include -L${mcf}/lib -static -o wingtm.exe helper.cpp
      unzip -j ${windowsDriver} camera/IntelDeviceMFT64.dll camera/SC200PC_KAFC917_PTL.aiqb
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 libwingtm.so $out/lib/libwingtm.so
      install -Dm644 -t $out/share/wingtm wingtm.exe IntelDeviceMFT64.dll \
        SC200PC_KAFC917_PTL.aiqb sc200pc_1080p.aiccfg
      mkdir -p $out/bin
      cat >$out/bin/wingtm-helper <<EOF
      #!/bin/sh
      # WINGTM_CMD for libwingtm.so. The Wine prefix is created on first use (about 15 s).
      export WINEPREFIX=\''${WINGTM_PREFIX:-/var/cache/wingtm-prefix-\$(id -u)}
      export WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" MANGOHUD=0 DISABLE_MANGOHUD=1
      LOG=\''${WINGTM_LOG:-/dev/null}
      [ -d "\$WINEPREFIX" ] || ${wine}/bin/wineboot -i >&2 2>>"\$LOG"
      cd $out/share/wingtm
      exec ${wine}/bin/wine wingtm.exe dll=IntelDeviceMFT64.dll aiqb=SC200PC_KAFC917_PTL.aiqb \
        cfg=sc200pc_1080p.aiccfg 2>>"\$LOG"
      EOF
      chmod 755 $out/bin/wingtm-helper
      runHook postInstall
    '';
  }
