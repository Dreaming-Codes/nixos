{pkgs, ...}: let
  # Samsung's Windows profiles for the SDC4228 OLED panel. SDC4228S/P/A rely on
  # an MHC2 matrix that Windows loads into the GPU; niri applies no such
  # transform, so only the native SDC4228 profile describes the panel on Linux.
  defaultProfile = "SDC4228.icm";

  profiles = pkgs.runCommand "samsung-sdc4228-icc" {} ''
    install -Dm644 -t $out/share/color/icc/samsung ${./icc}/*.icm
    ln -s ${defaultProfile} $out/share/color/icc/samsung/default.icm
  '';
in {
  services.colord.enable = true;
  environment.systemPackages = [profiles];
  environment.pathsToLink = ["/share/color"];
}
