{...}: {
  config = {
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
    };
  };
}
