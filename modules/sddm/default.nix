{
  pkgs,
  ...
}: let
  # Custom SDDM theme based on Breeze with per-user session support
  breezePerUserTheme = pkgs.runCommand "sddm-breeze-per-user" {
    breezeTheme = "${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze";
  } ''
    mkdir -p $out
    
    # Copy all files from original breeze theme (--no-preserve to make writable)
    cp -r --no-preserve=mode,ownership $breezeTheme/* $out/
    
    # Override with our modified files
    cp ${./theme/Main.qml} $out/Main.qml
    cp ${./theme/SessionButton.qml} $out/SessionButton.qml
    cp ${./theme/metadata.desktop} $out/metadata.desktop
  '';
in {
  # Set theme to the path of our custom theme
  services.displayManager.sddm.theme = "${breezePerUserTheme}";
}
