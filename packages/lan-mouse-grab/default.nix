{
  lib,
  rustPlatform,
  pkg-config,
  gst_all_1,
  wayland,
  dbus,
  bluez,
  makeWrapper,
  v4l-utils,
}:
rustPlatform.buildRustPackage {
  pname = "lan-mouse-grab";
  version = "0.1.0";

  src = ./.;

  cargoHash = "sha256-wHpfIvuhgYTcPTfC9aiuMOquIoPba0/pdsU8xgeca98=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    wayland
    dbus
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-vaapi
  ];

  postInstall = ''
    wrapProgram $out/bin/lan-mouse-grab \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "$GST_PLUGIN_SYSTEM_PATH_1_0" \
      --prefix PATH : "${v4l-utils}/bin:${bluez}/bin"
  '';

  meta = with lib; {
    description = "Capture card video display + Classic BT HID input forwarding";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
