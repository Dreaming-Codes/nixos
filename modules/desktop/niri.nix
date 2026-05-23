{pkgs, ...}: {
  programs.niri = {
    enable = true;
    useNautilus = false;
  };

  environment.systemPackages = with pkgs; [
    niri
    niriswitcher
    xwayland-satellite
  ];
}
