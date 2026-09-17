{lib, stdenvNoCC}:
stdenvNoCC.mkDerivation {
  pname = "galaxybook6-camera-userspace";
  version = "0.9.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 ${./sc200pc.yaml} \
      "$out/share/libcamera/ipa/simple/sc200pc.yaml"
    install -Dm644 ${./50-ipu7-hide-v4l2.conf} \
      "$out/share/galaxybook6-camera/50-ipu7-hide-v4l2.conf"
    runHook postInstall
  '';

  meta = {
    description = "libcamera tuning for Book6 Ultra SC200PC";
    homepage = "https://github.com/MarcoGlauser/galaxybook6-ultra-camera";
    license = lib.licenses.cc0;
    platforms = ["x86_64-linux"];
  };
}
