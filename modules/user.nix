{
  config,
  pkgs,
  ...
}: {
  security = {
    # auto unlock kwallet on boot
    pam = {
      services = {
        "dreamingcodes" = {
          kwallet = {
            enable = true;
            package = pkgs.kdePackages.kwallet-pam;
          };
        };
      };
    };
  };
  users.users.dreamingcodes = {
    isNormalUser = true;
    description = "DreamingCodes";
    extraGroups = ["networkmanager" "wheel" "docker" "libvirtd" "kvm" "adbusers" "input" "plugdev" "pipewire" "wireshark" "dialout"];
    shell = pkgs.fish;
  };
}
