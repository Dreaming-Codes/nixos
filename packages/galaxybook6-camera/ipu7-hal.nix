{
  fetchFromGitHub,
  fetchurl,
  ipu7x-camera-hal,
  ipu7-camera-bins,
  python3,
  unzip,
}: let
  upstream = import ./upstream.nix {inherit fetchFromGitHub;};

  # Pinned by upstream: the converted graph depends on this release's data layout.
  bins = ipu7-camera-bins.overrideAttrs {
    version = "0-unstable-2025-12-10";
    src = fetchFromGitHub {
      owner = "intel";
      repo = "ipu7-camera-bins";
      rev = "ed16ac75642f181e36607c855a889245f06cb6ec";
      hash = "sha256-ygJtgbAbaK6Sec44dIGbF5U4WN30TxHgv31f6Ri4KZk=";
    };
  };

  # Samsung's camera driver (Intel camera driver 71.26100.23.20550, sc200pc.inf 71.26100.0.11).
  windowsDriver = fetchurl {
    url = "https://downloadcenter.samsung.com/content/DR/202608/20260811081131834/BASW-A4296A0R_1063.ZIP";
    hash = "sha256-mZnTw8woT12RXuDnrfZWvqAA4YdY7NIU6Uk8w/tPqNY=";
  };
in
  (ipu7x-camera-hal.override {
    ipuVersion = "ipu75xa";
    ipu7-camera-bins = bins;
  })
  .overrideAttrs (old: {
    version = "0-unstable-2025-12-10";

    src = fetchFromGitHub {
      owner = "intel";
      repo = "ipu7-camera-hal";
      rev = "e5172cc3d57c90c03ef81c860f9856452afed693";
      hash = "sha256-pica+qa9RMudr2acXm6u6gG4JHWiI9YHhfrRmtISpyc=";
    };

    patches = ["${upstream}/ipu7-hal/hal-e5172cc.patch" ./hal-aic-operation-mode-0.patch];

    nativeBuildInputs = old.nativeBuildInputs ++ [python3 unzip];

    # Upstream ipu7-hal/build.sh's graph conversion: Windows graph rebuilt as Linux graph 100002.
    postInstall =
      old.postInstall
      + ''
        U=${upstream}/ipu7-hal
        C=$out/etc/camera/ipu75xa
        H=$NIX_BUILD_TOP/$sourceRoot/modules/ipu_desc/ipu75xa
        W=$NIX_BUILD_TOP/sc200pc
        mkdir -p $W

        unzip -j ${windowsDriver} camera/graph_settings_SC200PC_KAFC917_PTL.bin \
          camera/SC200PC_KAFC917_PTL.aiqb -d $W
        (cd $W && sha256sum -c) <<EOF
        acd119628426009170a12ee86ed7fa7e1bd7650e259339b43551b4685f8c9bd0  graph_settings_SC200PC_KAFC917_PTL.bin
        65b75702f33e880f9976cf51a3afa41e577dd33c1f1995e9a9fdfd1e29e5c99e  SC200PC_KAFC917_PTL.aiqb
        EOF

        cp $U/sc200pc-uf.json $C/sensors/
        # Samsung's tuning as Windows uses it. Its ISP tuning is keyed to the Windows DOL
        # stream ids; without the Linux ids AIC runs bnlm/xnr/TNR on library defaults.
        python3 $U/aiqb-stream-ids.py $W/SC200PC_KAFC917_PTL.aiqb $C/SC200PC_KAFC917_PTL.aiqb
        python3 $U/patch-hashes.py $W/graph_settings_SC200PC_KAFC917_PTL.bin $W/sc200pc_patched.bin
        python3 $U/gen-kernel-meta.py $H/Ipu75xaStaticGraphAutogen.cpp $W/kernel_meta.h \
          LbffDol2Inputs LbffBayer BbpsWithTnr
        # Each setting keeps the Windows ISP tuning mode (0 at 1080p, 1 at 720p, 2 below), which
        # PipeLine::updateIspTuningMode loads as the aiqb LISP block, as the Windows MFT does.
        install -m644 $U/convert-100002.cpp $W/
        patch -d $W -p2 < ${./convert-100002-keep-tuning-modes.patch}
        $CXX -std=c++17 -w -I$H -I$W -o $W/convert-100002 $W/convert-100002.cpp
        $W/convert-100002 $W/sc200pc_patched.bin $C/gcss/SC200PC_KAFC917.IPU75XA.bin

        sed -i 's/"availableSensors": \[/"availableSensors": [\n            "sc200pc-uf-0",/' \
          $C/libcamhal_configs.json
      '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      C=$out/etc/camera/ipu75xa
      H=$NIX_BUILD_TOP/$sourceRoot/modules/ipu_desc/ipu75xa
      $CXX -std=c++17 -w -I$H -o check-graph ${upstream}/ipu7-hal/check-graph.cpp \
        $H/Ipu75xaStaticGraphReaderAutogen.cpp $H/Ipu75xaStaticGraphAutogen.cpp
      ./check-graph $C/gcss/SC200PC_KAFC917.IPU75XA.bin
      python3 - $C <<'EOF'
      import json, re, sys
      c = sys.argv[1]
      def load(p):  # jsoncpp accepts // comment lines
          return json.loads(re.sub(r"(?m)^\s*//.*$", "", open(p).read()))
      configs = load(f"{c}/libcamhal_configs.json")
      assert "sc200pc-uf-0" in json.dumps(configs), "sc200pc-uf-0 not registered"
      load(f"{c}/sensors/sc200pc-uf.json")
      open(f"{c}/SC200PC_KAFC917_PTL.aiqb", "rb").read()
      print("configuration ok")
      EOF
      python3 ${upstream}/ipu7-hal/aiqb-lisp.py $C/SC200PC_KAFC917_PTL.aiqb > lisp.txt
      if grep -E 'flags 0xea6[ef]' lisp.txt; then
        echo "ISP tuning still keyed to Windows stream ids" >&2
        exit 1
      fi
      runHook postInstallCheck
    '';

    passthru = old.passthru // {inherit bins upstream;};
  })
