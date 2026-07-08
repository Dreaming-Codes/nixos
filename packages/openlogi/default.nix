{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  libxkbcommon,
  libxcb,
  libx11,
}: let
  version = "0.6.19";

  srcs = {
    x86_64-linux = fetchurl {
      url = "https://github.com/AprilNEA/OpenLogi/releases/download/v${version}/openlogi-v${version}-linux-amd64.deb";
      hash = "sha256-heEq68pLxcmLewqqShXUNkxFxnsou8lrrvFtWau/LMQ=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/AprilNEA/OpenLogi/releases/download/v${version}/openlogi-v${version}-linux-arm64.deb";
      hash = "sha256-NnUiM24tBzhdIyNvtDKd4e9HEZpKVWLijOBpinCfTFE=";
    };
  };

  src =
    srcs.${stdenv.hostPlatform.system}
      or (throw "openlogi: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "openlogi";
    inherit version src;

    nativeBuildInputs = [
      autoPatchelfHook
      dpkg
    ];

    buildInputs = [
      libxkbcommon
      libxcb
      libx11
      stdenv.cc.cc.lib
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib/udev/rules.d $out/share/applications $out/share/icons

      install -Dm755 usr/bin/openlogi $out/bin/openlogi
      install -Dm755 usr/bin/openlogi-gui $out/bin/openlogi-gui
      install -Dm755 usr/bin/openlogi-agent $out/bin/openlogi-agent

      # NixOS expects udev rules under lib/udev/rules.d (via services.udev.packages).
      install -Dm644 etc/udev/rules.d/70-openlogi.rules $out/lib/udev/rules.d/70-openlogi.rules

      install -Dm644 usr/share/applications/openlogi.desktop $out/share/applications/openlogi.desktop
      cp -r usr/share/icons/hicolor $out/share/icons/

      # Upstream .deb ships an unexpanded @BINDIR@ placeholder; point Exec at our store path.
      substituteInPlace $out/share/applications/openlogi.desktop \
        --replace-fail 'Exec=openlogi-gui' "Exec=$out/bin/openlogi-gui"

      runHook postInstall
    '';

    meta = {
      description = "Native, local-first alternative to Logitech Options+ for HID++ mice";
      homepage = "https://github.com/AprilNEA/OpenLogi";
      changelog = "https://github.com/AprilNEA/OpenLogi/releases/tag/v${version}";
      license = with lib.licenses; [
        asl20
        mit
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "openlogi-gui";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
