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

    # modules_install signs each module (writing the .ko.cer the module
    # aggregator needs); updates/ overrides the in-tree ipu_bridge.
    installPhase = ''
      runHook preInstall
      make -C ${kdir} M="$PWD" $makeFlags \
        INSTALL_MOD_PATH="$out" INSTALL_MOD_DIR=updates modules_install
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
