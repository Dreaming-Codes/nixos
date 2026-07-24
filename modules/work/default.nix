{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.work;
in {
  options.dreaming.work.enable = lib.mkEnableOption "work (Neuralink) tooling: AI gateway + internal CA";

  config = lib.mkIf cfg.enable {
    home-manager.users.dreamingcodes.imports = [../../home/work.nix];

    # Neuralink Internal Root CA. The cert lives in this repo under
    # secrets/certs/ encrypted at rest with git-crypt; the working tree holds
    # the decrypted PEM, so security.pki bakes it into the system CA bundle at
    # build time (no --impure needed).
    # secrets/work/ (llm_proxy.py) is also git-crypt'd and consumed by HM as
    # nlk-llm-proxy for Grok / OpenCode / Zed gateway auth.
    security.pki.certificateFiles = [
      ../../secrets/certs/neuralink-internal-root-ca.crt
    ];

    services.tailscale.enable = true;

    # Keychron: hidraw access for VIA / Keychron Launcher (vendor 3434).
    hardware.keyboard.qmk.enable = true;
    services.udev.packages = [pkgs.keychron-udev-rules];
  };
}
