{
  fetchFromGitHub,
  gst_all_1,
  libdrm,
  hal,
}: let
  upstream = import ./upstream.nix {inherit fetchFromGitHub;};
in
  (gst_all_1.icamerasrc-ipu7x.override {ipu7x-camera-hal = hal;}).overrideAttrs {
    version = "0-unstable-2025-09-26";

    src = fetchFromGitHub {
      owner = "intel";
      repo = "icamerasrc";
      rev = "4fb31db76b618aae72184c59314b839dedb42689";
      hash = "sha256-BYURJfNz4D8bXbSeuWyUYnoifozFOq6rSfG9GBKVoHo=";
    };

    patches = ["${upstream}/ipu7-hal/icamerasrc-4fb31db.patch"];

    # Upstream builds without --enable-gstdrmformat, so no gst-plugins-bad or libva.
    configureFlags = [];
    buildInputs = [
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      hal
      libdrm
    ];

    doInstallCheck = true;
    nativeInstallCheckInputs = [gst_all_1.gstreamer];
    installCheckPhase = ''
      runHook preInstallCheck
      GST_REGISTRY=$TMPDIR/registry.bin GST_PLUGIN_PATH=$out/lib/gstreamer-1.0 \
        gst-inspect-1.0 icamerasrc > inspect.txt
      grep -q 'fps-range' inspect.txt
      runHook postInstallCheck
    '';
  }
