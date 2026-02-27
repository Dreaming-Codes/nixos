{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  packages = with pkgs; [
    pkg-config
    dbus
    wayland
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-vaapi
    v4l-utils
    bluez
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.dbus
    pkgs.wayland
    pkgs.glib
    pkgs.gst_all_1.gstreamer
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gst-plugins-bad
    pkgs.gst_all_1.gst-vaapi
  ];

  shellHook = ''
    export PKG_CONFIG_PATH="${pkgs.dbus.dev}/lib/pkgconfig:${pkgs.glib.dev}/lib/pkgconfig:${pkgs.gst_all_1.gstreamer.dev}/lib/pkgconfig:${pkgs.gst_all_1.gst-plugins-base.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
    echo "lan-mouse-grab dev shell ready"
    echo "Run: cargo run"
  '';
}
