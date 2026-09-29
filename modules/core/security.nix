{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.core.security;
in {
  options.dreaming.core.security.enable =
    lib.mkEnableOption "core security policy (polkit/sudo/pam/fscrypt)"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.UPower.PowerProfiles.switch-profile" &&
          subject.isInGroup("wheel")
        ) {
          return polkit.Result.YES;
        }
      });
      polkit.addRule(function(action, subject) {
        if (subject.isInGroup("wheel"))
          return polkit.Result.YES;
      });
    '';

    # NixOS ships pkexec without the setuid bit, so it refuses to run.
    # Wrap it so polkit escalation works; the wheel rule above authorizes it.
    security.wrappers.pkexec = {
      owner = "root";
      group = "root";
      setuid = true;
      source = "${pkgs.polkit.bin}/bin/pkexec";
    };

    security.rtkit.enable = true;
    security.sudo-rs.enable = true;
    security.sudo-rs.wheelNeedsPassword = false;
    security.pam.services.login.kwallet.enable = true;
    security.pam.services.greetd.kwallet = {
      enable = true;
      forceRun = true;
    };
    security.pam.loginLimits = [
      {
        domain = "*";
        type = "soft";
        item = "nofile";
        value = "10000";
      }
    ];

    # Disable man page cache generation since it's very slow and fish enable it by default
    documentation.man.cache.enable = false;
  };
}
