{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.dreaming.services.nbhCache;
in {
  # Merging nbh-ssh-ng-client means importing the client module once, from one file.
  imports = [inputs.nix-build-heaven.nixosModules.client];

  options.dreaming.services.nbhCache.enable =
    lib.mkEnableOption "the Nix Build Heaven S3 cache: substitute from it and keep this host's roots in it";

  config = lib.mkIf cfg.enable {
    sops.secrets.nbh_cache_credentials = {
      sopsFile = ../../secrets/nbh-cache-${config.networking.hostName}.yaml;
      mode = "0400";
    };
    services.nbh.cache = {
      enable = true;
      credentialsFile = config.sops.secrets.nbh_cache_credentials.path;
    };
  };
}
