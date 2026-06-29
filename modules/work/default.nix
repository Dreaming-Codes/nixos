{
  config,
  lib,
  ...
}: let
  cfg = config.dreaming.work;
in {
  options.dreaming.work.enable = lib.mkEnableOption "work (Neuralink/Bedrock) tooling: opencode model + AWS profile";

  config = lib.mkIf cfg.enable {
    home-manager.users.dreamingcodes.imports = [../../home/work.nix];

    # Neuralink Internal Root CA. The cert lives in this repo under
    # secrets/certs/ encrypted at rest with git-crypt; the working tree holds
    # the decrypted PEM, so security.pki bakes it into the system CA bundle at
    # build time (no --impure needed).
    security.pki.certificateFiles = [
      ../../secrets/certs/neuralink-internal-root-ca.crt
    ];
  };
}
