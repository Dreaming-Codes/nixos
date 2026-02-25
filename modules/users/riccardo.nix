{
  pkgs,
  lib,
  config,
  nix-index-database,
  ...
}: {
  # Riccardo user (desktop only)
  users.users.riccardo = {
    isNormalUser = true;
    description = "Riccardo";
    extraGroups = config.users.commonGroups;
    shell = pkgs.fish;
  };

  # PAM kwallet for riccardo
  security.pam.services."riccardo" = {
    kwallet = {
      enable = true;
      package = pkgs.kdePackages.kwallet-pam;
    };
  };

  # Riccardo Home Manager configuration
  home-manager.users.riccardo = {
    imports = [
      nix-index-database.homeModules.nix-index
      ../../home/common.nix
    ];
    home.stateVersion = "25.11";
  };
}
