{pkgs, ...}: {
  virtualisation.spiceUSBRedirection.enable = true;

  systemd.tmpfiles.rules = [
    "f /dev/shm/looking-glass 0660 dreamingcodes kvm -"
  ];
  environment.systemPackages = with pkgs; [
    looking-glass-client
    ddcutil
  ];
}
