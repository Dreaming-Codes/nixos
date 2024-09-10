{ pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # amd gpu utility
    lact
  ];
}
