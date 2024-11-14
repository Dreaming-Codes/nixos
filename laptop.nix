{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [ nrfutil ];
  nixpkgs.config.segger-jlink.acceptLicense = true;
  services = {
    udev = {
      extraRules = ''
        SUBSYSTEM=="tty", ATTRS{idVendor}=="1915", ATTRS{idProduct}=="522a", ATTRS{serial}=="84014353616C81E9", GROUP="wireshark", MODE="0666"
      '';
    };
  };
  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  # Enable rocm support for the iGPU on the laptop
  nixpkgs.config.rocmSupport = true;
  # Enable cuda support for the dGPU on the laptop
  nixpkgs.config.cudaSupport = true;

  users = { users.dreamingcodes = { extraGroups = [ "wireshark" ]; }; };

}
