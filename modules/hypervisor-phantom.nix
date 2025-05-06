{
  pkgs,
  lib,
  ...
}: {
  boot = {
    extraModprobeConfig = ''
      options kvm ignore_msrs=1
    '';
  };
}
