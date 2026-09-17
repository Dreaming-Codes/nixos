{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}: let
  kdir = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
in
  stdenv.mkDerivation {
    pname = "galaxybook6-camera";
    version = "0.9.0";

    src = ./src;

    nativeBuildInputs = kernel.moduleBuildDependencies;

    makeFlags =
      kernelModuleMakeFlags
      ++ [
        "KERNELRELEASE=${kernel.modDirVersion}"
      ];

    buildPhase = ''
      runHook preBuild
      make -C ${kdir} M="$PWD" $makeFlags modules
      runHook postBuild
    '';

    enableParallelBuilding = true;
    dontStrip = true;
    dontPatchELF = true;

    # updates/ overrides the in-tree ipu_bridge; extra/ holds sc200pc.
    installPhase = ''
      runHook preInstall
      install -Dm644 sc200pc.ko \
        "$out/lib/modules/${kernel.modDirVersion}/extra/sc200pc.ko"
      install -Dm644 ipu-bridge.ko \
        "$out/lib/modules/${kernel.modDirVersion}/updates/ipu-bridge.ko"
      runHook postInstall
    '';

    meta = {
      description = "Galaxy Book6 Ultra SC200PC sensor + ipu-bridge SSLC2000";
      homepage = "https://github.com/MarcoGlauser/galaxybook6-ultra-camera";
      license = lib.licenses.gpl2Only;
      platforms = ["x86_64-linux"];
      broken = kernel.kernelOlder "7.0";
    };
  }
