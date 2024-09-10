{ pkgs, ... }: {
  environment.systemPackages = with pkgs;
    [
      # amd gpu utility
      lact
    ];

  systemd.services.lact = {
    description = "AMDGPU Control Daemon";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { ExecStart = "${pkgs.lact}/bin/lact daemon"; };
    enable = true;
  };

  boot.kernelParams = [ "amdgpu.ppfeaturemask=0xFFF7FFFF" ];
}
