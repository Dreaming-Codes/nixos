{
  stdenv,
  lib,
  appimageTools,
  fetchurl,
  makeDesktopItem,
  copyDesktopItems,
}: let
  pname = "helium-browser";
  version = "0.6.3.1";

  architectures = {
    "x86_64-linux" = {
      arch = "x86_64";
      hash = "sha256-N7JpLLOdsnYuzYreN1iaHI992MR2SuXTmXHfa6fd1UU=";
    };
    "aarch64-linux" = {
      arch = "arm64";
      hash = "sha256-B81KARcFmMCRHXSy/6YNSEZ1foYQfD1jLNHTbDYRuK4=";
    };
  };

  src = let
    inherit (architectures.${stdenv.hostPlatform.system}) arch hash;
  in
    fetchurl {
      url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-${arch}.AppImage";
      inherit hash;
    };
in
  appimageTools.wrapType2 {
    inherit pname version src;
    nativeBuildInputs = [copyDesktopItems];
    desktopItems = [
      (makeDesktopItem {
        })
    ];
    meta = {
      platforms = lib.attrNames architectures;
    };
  }
