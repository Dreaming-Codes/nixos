{
  config,
  pkgs,
  ...
}: {
  users.users.dreamingcodes = {
    isNormalUser = true;
    description = "DreamingCodes";
    extraGroups = ["networkmanager" "wheel" "docker" "libvirtd" "kvm" "adbusers" "input" "plugdev" "pipewire" "wireshark"];
    shell = pkgs.fish;
  };
}
