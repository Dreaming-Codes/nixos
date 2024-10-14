{ config, pkgs, ... }: {
  garuda = {
    performance-tweaks = {
      cachyos-kernel = true;
      enable = true;
    };
    system = { type = "dreamingized"; };
  };
  chaotic.scx = {
    # enable = true;
    # scheduler = "scx_rusty"; BROKEN
  };
}
