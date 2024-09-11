{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # amd gpu utility
    lact
    looking-glass-client
    scream
  ];

  systemd.services.lact = {
    description = "AMDGPU Control Daemon";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { ExecStart = "${pkgs.lact}/bin/lact daemon"; };
    enable = true;
  };

  systemd.tmpfiles.rules = [
    "f /dev/shm/looking-glass 0660 dreamingcodes kvm -"
    "f /dev/shm/scream 0660 dreamingcodes kvm -"
  ];

  systemd.user.services.scream-ivshmem = {
    enable = true;
    description = "Scream IVSHMEM";
    serviceConfig = {
      ExecStart = "${pkgs.scream}/bin/scream-ivshmem-pulse /dev/shm/scream";
      Restart = "always";
    };
    wantedBy = [ "multi-user.target" ];
    requires = [ "pipewire.service" ];
  };

  virtualisation = {
    vfio = {
      enable = true;
      IOMMUType = "intel";
      blacklistNvidia = true;
      devices = [ "10de:1b81" "10de:10f0" ];
    };
    kvmfr = { enable = false; };
  };

  boot.kernelParams = [
    "pcie_acs_override=downstream"
    "intel_iommu=on"
    "iommu=pt"
    "amdgpu.ppfeaturemask=0xFFF7FFFF"
    ''vfio-pci.ids="10de:1b81,10de:10f0"''
  ];
}
