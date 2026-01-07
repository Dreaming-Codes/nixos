{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    lc3tools
  ];
}
