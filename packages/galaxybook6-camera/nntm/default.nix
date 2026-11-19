{
  stdenv,
  fetchurl,
  gst_all_1,
  openvino,
  pkg-config,
  python3,
  unzip,
}: let
  # The network and the tuning file are proprietary: they are extracted at build time and
  # never enter this repository.
  windowsDriver = import ../windows-driver.nix {inherit fetchurl;};
in
  stdenv.mkDerivation {
    pname = "gst-nntm";
    version = "1.0";

    src = ./.;

    nativeBuildInputs = [
      pkg-config
      unzip
      (python3.withPackages (ps: [ps.numpy ps.openvino]))
    ];
    buildInputs = [
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      openvino
    ];

    # Each pixel operation is rounded to half precision on its own: no contraction, no fast-math.
    # -O3 unrolls the lane loops of nntm.c; at -O2 the kernel is 2.5 times slower.
    buildPhase = ''
      runHook preBuild
      $CC -O3 -mavx2 -mf16c -ffp-contract=off -Wall -Werror -fPIC -shared \
        -DPACKAGE='"nntm"' -DNNTM_DATA_DIR="\"$out/share/nntm\"" \
        $(pkg-config --cflags gstreamer-video-1.0 openvino) gstnntm.c backend_cpu.c nntm.c \
        $(pkg-config --libs gstreamer-video-1.0) $(pkg-config --libs-only-L openvino) -lopenvino_c -lm \
        -o libgstnntm.so
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 libgstnntm.so -t $out/lib/gstreamer-1.0
      mkdir -p $out/share/nntm driver
      unzip -j ${windowsDriver} camera/intelic_data.bin camera/SC200PC_KAFC917_PTL.aiqb -d driver
      python3 extract.py driver/intelic_data.bin driver/SC200PC_KAFC917_PTL.aiqb $out/share/nntm
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      mkdir check
      GST_REGISTRY=$PWD/check/registry.bin GST_PLUGIN_PATH=$out/lib/gstreamer-1.0 \
        python3 check.py $out/share/nntm check
      runHook postInstallCheck
    '';
  }
