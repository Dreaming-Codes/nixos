{
  config,
  pkgs,
  lib,
  ...
}: let
  ageKeyFile = "/home/dreamingcodes/.nixos/secrets/identity.age";
in {
  sops = {
    # Default sops file containing all secrets
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Age key for decryption (only exists on real systems, not CI)
    age.keyFile = ageKeyFile;

    # Secrets definition
    secrets = {
      github_token = {
        # Will be available at /run/secrets/github_token
        owner = "dreamingcodes";
        group = "users";
        mode = "0400";
      };
      telegram_bot_token = {
        owner = "dreamingcodes";
        group = "users";
        mode = "0400";
      };
    };

    # Template for nix access-tokens configuration
    templates."nix-access-tokens.conf" = {
      content = ''
        access-tokens = github.com=${config.sops.placeholder.github_token}
      '';
    };
  };

  # Use the templated access-tokens file
  # The !include directive gracefully handles missing files
  nix.extraOptions = ''
    !include ${config.sops.templates."nix-access-tokens.conf".path}
  '';

  system.activationScripts.setupSecrets.text = lib.mkMerge [
    (lib.mkBefore ''
      _sops_status_before=$_status
    '')
    (lib.mkAfter ''
      if [ "''${_localstatus:-0}" -gt 0 ] && [ ! -e ${lib.escapeShellArg ageKeyFile} ]; then
        echo "warning: ${ageKeyFile} is missing; ignoring sops-nix activation failure"
        _status=$_sops_status_before
        _localstatus=0
      fi
    '')
  ];
}
