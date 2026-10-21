{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.dreaming.services.nbh;
  secret = key: {
    sopsFile = ../../secrets/nbh-gate.yaml;
    inherit key;
    mode = "0400";
    owner = "root";
    group = "root";
    restartUnits = ["nbh-gate.service"];
  };
in {
  imports = [inputs.nix-build-heaven.nixosModules.client];

  options.dreaming.services.nbh = {
    enable =
      lib.mkEnableOption "big-parallel builds on the Nix Build Heaven EC2 builder over ssh-ng";
    aws = {
      account = lib.mkOption {
        type = lib.types.strMatching "[0-9]{12}";
        description = "AWS account of the gate's key and of the cache bucket.";
      };
      region = lib.mkOption {
        type = lib.types.str;
        description = "AWS region of the builders and the cache bucket.";
      };
    };
    cache = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Substitute from the Nix Build Heaven S3 cache and keep the running system's closure rooted in it.";
      };
      bucket = lib.mkOption {
        type = lib.types.str;
        description = "S3 bucket of the cache.";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        description = "Public key that signs the cache's narinfos.";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # pki-init keeps an existing ssh_host_ca, so the gate uses these and writes nothing.
      sops.secrets = {
        nbh_gate_credentials = secret "nbh_gate_credentials";
        "nbh-pki/ssh_host_ca" = secret "nbh_pki_ssh_host_ca";
        "nbh-pki/ssh_client" = secret "nbh_pki_ssh_client";
        "nbh-pki/ssh_client.pub" = secret "nbh_pki_ssh_client_pub";
        "nbh-pki/ssh_known_hosts" = secret "nbh_pki_ssh_known_hosts";
      };
      services.nbh = {
        enable = true;
        pkiDir = dirOf config.sops.secrets."nbh-pki/ssh_host_ca".path;
        gate = {
          aws = {
            inherit (cfg.aws) account region;
            profile = "nbh-gate";
            credentialsFile = config.sops.secrets.nbh_gate_credentials.path;
          };
          extraArgs = [
            "--instance-types" "c7i.24xlarge,c7a.24xlarge,m7a.24xlarge"
            "--max-price" "0.80"
          ];
        };
      };
    }
    (lib.mkIf cfg.cache.enable {
      sops.secrets.nbh_cache_credentials = {
        sopsFile = ../../secrets/nbh-cache.yaml;
        mode = "0400";
      };
      services.nbh.cache = {
        enable = true;
        inherit (cfg.aws) account region;
        inherit (cfg.cache) bucket publicKey;
        credentialsFile = config.sops.secrets.nbh_cache_credentials.path;
      };
    })
  ]);
}
