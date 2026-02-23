{
  lib,
  rustPlatform,
  pkg-config,
  gst_all_1,
  wayland,
  makeWrapper,
  v4l-utils,
}:
rustPlatform.buildRustPackage {
  pname = "lan-mouse-grab";
  version = "0.1.0";

  src = ./.;

  cargoHash = "sha256-R9poCrlNm/3QFum8D3jz0LtcWT1oqZ7aPjujUFJP2Q4=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    wayland
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-vaapi
  ];

  postInstall = ''
    wrapProgram $out/bin/lan-mouse-grab \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : "$GST_PLUGIN_SYSTEM_PATH_1_0" \
      --prefix PATH : "${v4l-utils}/bin"
  '';

  meta = with lib; {
    description = "Capture card video display + input forwarding via lan-mouse protocol";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
