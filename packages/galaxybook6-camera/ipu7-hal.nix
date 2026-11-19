{
  fetchFromGitHub,
  fetchurl,
  ipu7x-camera-hal,
  ipu7-camera-bins,
  openvino,
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

  windowsDriver = import ./windows-driver.nix {inherit fetchurl;};
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

    patches = [
      "${upstream}/ipu7-hal/hal-e5172cc.patch"
      ./hal-aic-operation-mode-0.patch
      ./hal-yuv-range.patch
      ./hal-face-detection.patch
      ./hal-two-exposures.patch
      ./hal-3a-inputs.patch
      ./hal-nntm-params.patch
    ];

    cmakeFlags = old.cmakeFlags ++ ["-DFACE_DETECTION=ON"];
    buildInputs = old.buildInputs ++ [openvino];
    nativeBuildInputs = old.nativeBuildInputs ++ [(python3.withPackages (ps: [ps.numpy])) unzip];

    env = (old.env or {}) // {NIX_CFLAGS_COMPILE = "${old.env.NIX_CFLAGS_COMPILE or ""} -DDOL_FEATURE";};

    postInstall =
      old.postInstall
      + ''
        U=${upstream}/ipu7-hal
        C=$out/etc/camera/ipu75xa
        H=$NIX_BUILD_TOP/$sourceRoot/modules/ipu_desc/ipu75xa
        W=$NIX_BUILD_TOP/sc200pc
        mkdir -p $W

        unzip -j ${windowsDriver} camera/graph_settings_SC200PC_KAFC917_PTL.bin \
          camera/SC200PC_KAFC917_PTL.aiqb camera/intelic_data.bin -d $W
        (cd $W && sha256sum -c) <<EOF
        acd119628426009170a12ee86ed7fa7e1bd7650e259339b43551b4685f8c9bd0  graph_settings_SC200PC_KAFC917_PTL.bin
        65b75702f33e880f9976cf51a3afa41e577dd33c1f1995e9a9fdfd1e29e5c99e  SC200PC_KAFC917_PTL.aiqb
        EOF

        # The sensor applies exposure and gain written as plain registers on the next frame.
        # v4l2loopback consumers assume limited-range YUV.
        # faceEngineRunningInterval is milliseconds of frame time.
        substitute $U/sc200pc-uf.json $C/sensors/sc200pc-uf.json \
          --replace-fail '"exposureLag":  2' '"exposureLag": 1' \
          --replace-fail '"gainLag": 2' '"gainLag": 1' \
          --replace-fail '"digitalGainLag": 0' '"digitalGainLag": 1' \
          --replace-fail '"yuvColorRangeMode": "full"' '"yuvColorRangeMode": "reduced"' \
          --replace-fail 'availableFaceDetectModes" : [0]' 'availableFaceDetectModes" : [0, 1]' \
          --replace-fail '"psysBundleWithAic": false,' '"psysBundleWithAic": false,
                "faceAeEnabled": true, "faceEngineVendor": 2, "runFaceWithSyncMode": true,
                "faceEngineRunningInterval": 66,' \
          --replace-fail '"link": [' '"control": [
              {
                "name": "sc200pc $I2CBUS", "ctrlId": "V4L2_CID_WDR_MODE", "value": 1,
                "ctrlName": "two exposure streams"
              }
            ],
            "link": [
              {
                "srcName": "Intel IPU7 CSI2 $CSI_PORT", "srcPad": 2,
                "sinkName": "Intel IPU7 ISYS Capture 1", "sinkPad": 0, "enable": true
              },' \
          --replace-fail '"videonode": [' '"videonode": [
              {
                "name": "Intel IPU7 ISYS Capture 1", "videoNodeType": "VIDEO_GENERIC_SHORT_EXPO"
              },'
        python3 - $W/intelic_data.bin $C <<'EOF'
        import runpy, sys
        blobs = runpy.run_path("${./nntm/extract.py}")["blobs"]
        names = {"15559407078137448213": "centernet_face.xml", "15378421583209103717": "centernet_face.bin"}
        for key, data in blobs(open(sys.argv[1], "rb").read()):
            if key in names:
                open(f"{sys.argv[2]}/{names.pop(key)}", "wb").write(data)
        assert not names, names
        EOF
        install -m644 $W/SC200PC_KAFC917_PTL.aiqb $C/
        python3 $U/patch-hashes.py $W/graph_settings_SC200PC_KAFC917_PTL.bin $W/sc200pc_patched.bin
        python3 $U/gen-kernel-meta.py $H/Ipu75xaStaticGraphAutogen.cpp $W/kernel_meta.h \
          LbffDol2Inputs BbpsWithTnr
        $CXX -std=c++17 -w -I$H -I$W -o $W/graph-two-inputs ${./graph-two-inputs.cpp}
        $W/graph-two-inputs $W/sc200pc_patched.bin $C/gcss/SC200PC_KAFC917.IPU75XA.bin

        sed -i 's/"availableSensors": \[/"availableSensors": [\n            "sc200pc-uf-0",/' \
          $C/libcamhal_configs.json
      '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      C=$out/etc/camera/ipu75xa
      H=$NIX_BUILD_TOP/$sourceRoot/modules/ipu_desc/ipu75xa
      sed 's/id != 100002/(id != 100032 \&\& id != 100035)/' \
        ${upstream}/ipu7-hal/check-graph.cpp > check-graph.cpp
      grep -q 100035 check-graph.cpp
      $CXX -std=c++17 -w -I$H -o check-graph check-graph.cpp \
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
      if ! grep -qE 'flags 0xea6[ef]' lisp.txt; then
        echo "ISP tuning is not keyed to the graph's stream ids" >&2
        exit 1
      fi
      runHook postInstallCheck
    '';

    passthru = old.passthru // {inherit bins upstream;};
  })
