{
  config,
  pkgs,
  ...
}: {
  garuda = {
    performance-tweaks = {
      cachyos-kernel = true;
      enable = true;
    };
    system = {type = "dreamingized";};
  };
  services.scx = {
    enable = true;
    scheduler = "scx_bpfland";
    package = pkgs.scx.rustscheds;
  };
}
