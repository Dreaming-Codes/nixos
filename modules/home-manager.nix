{
  pkgs,
  lib,
  inputs,
  nix-index-database,
  ...
}: {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {inherit inputs;};

  home-manager.users.dreamingcodes = {
    home.stateVersion = "24.11";

    imports = [
      nix-index-database.homeModules.nix-index
      ./home-manager/common.nix
      ./home-manager/dreamingcodes.nix
    ];
  };
}
