{...}: {
  virtualisation.kvmfr.enable = true;
  virtualisation.kvmfr.devices = [
    {
      size = 256;

      permissions = {
        user = "dreamingcodes";
      };
    }
  ];
}
