{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.work;
  openlogi = pkgs.callPackage ../../packages/openlogi {};
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

    # OpenLogi — local-first Logitech Options+ alternative (HID++ mice).
    # Prebuilt Linux debs from upstream; nixpkgs only ships a Darwin build.
    environment.systemPackages = [openlogi];
    services.udev.packages = [openlogi];
    boot.kernelModules = ["uinput"];

    # Background agent owns HID++ I/O; GUI/CLI talk to it.
    systemd.user.services.openlogi-agent = {
      description = "OpenLogi background agent (Logitech HID++ device control)";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = "${openlogi}/bin/openlogi-agent";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

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
