{
  config,
  lib,
  pkgs,
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

    services.tailscale.enable = true;

    # Keychron: hidraw access for VIA / Keychron Launcher (vendor 3434).
    hardware.keyboard.qmk.enable = true;
    services.udev.packages = [pkgs.keychron-udev-rules];

    # Work-only secrets (from secrets/secrets.yaml)
    sops.secrets.xai_work_api_key = {
      owner = "dreamingcodes";
      group = "users";
      mode = "0400";
    };

    # systemd user sessions load ~/.config/environment.d/*.conf
    sops.templates."90-xai.conf" = {
      content = ''
        XAI_API_KEY=${config.sops.placeholder.xai_work_api_key}
      '';
      path = "/home/dreamingcodes/.config/environment.d/90-xai.conf";
      owner = "dreamingcodes";
      group = "users";
      mode = "0400";
    };
  };
}
