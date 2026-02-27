{pkgs, ...}: let
  lan-mouse-grab = pkgs.callPackage ../../packages/lan-mouse-grab {};
in {
  security.wrappers.lan-mouse-grab = {
    source = "${lan-mouse-grab}/libexec/lan-mouse-grab";
    capabilities = "cap_net_bind_service,cap_net_admin,cap_net_raw+eip";
    owner = "root";
    group = "root";
  };

  hardware = {
    cpu = {
      amd.updateMicrocode = true;
      intel.updateMicrocode = true;
    };
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    bluetooth = {
      enable = true;
      disabledPlugins = ["input"];
    };
  };
}
