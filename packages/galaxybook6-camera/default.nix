{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  fetchFromGitHub,
}: let
  kdir = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
  upstream = import ./upstream.nix {inherit fetchFromGitHub;};
in
  stdenv.mkDerivation {
    pname = "galaxybook6-camera";
    version = "0.9.0";

    src = ./src;

    # ipu-bridge is the running kernel's own copy plus the SSLC2000 entry.
    postUnpack = ''
      cp ${upstream}/dkms/sc200pc-0.9.0/sc200pc.c "$sourceRoot/"
      install -m644 ${kernel.src}/drivers/media/pci/intel/ipu-bridge.c "$sourceRoot/"
    '';

    patches = [./sc200pc-ctrl-lock.patch];

    # SmartSens SC200PC lists no link frequencies, so ISYS takes the rate from the
    # sensor driver's V4L2_CID_LINK_FREQ control.
    postPatch = ''
      substituteInPlace ipu-bridge.c --replace-fail \
        'static const struct ipu_sensor_config ipu_supported_sensors[] = {' \
        'static const struct ipu_sensor_config ipu_supported_sensors[] = {
      	IPU_SENSOR_CONFIG("SSLC2000", 0),'
    '';

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
