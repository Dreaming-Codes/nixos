{pkgs, ...}: {
  virtualisation = {
    docker.enable = true;
    spiceUSBRedirection.enable = true;
  };

  environment.systemPackages = with pkgs; [
    oxker
  ];
}
