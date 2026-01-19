{
  config,
  pkgs,
  lib,
  ...
}: {
  sops = {
    # Default sops file containing all secrets
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Age key for decryption (only exists on real systems, not CI)
    age.keyFile = "/home/dreamingcodes/.nixos/secrets/identity.age";

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

    # Template for ci-keyboard-leds service environment file
    templates."github_token_env" = {
      owner = "dreamingcodes";
      group = "users";
      mode = "0400";
      path = "/run/secrets/github_token_env";
      content = ''
        GITHUB_TOKEN=${config.sops.placeholder.github_token}
      '';
    };
  };

  # Use the templated access-tokens file
  # The !include directive gracefully handles missing files
  nix.extraOptions = ''
    !include ${config.sops.templates."nix-access-tokens.conf".path}
  '';
}
