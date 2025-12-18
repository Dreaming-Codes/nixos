{pkgs, ...}: {
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

  security.rtkit.enable = true;
  security.sudo-rs.enable = true;
  security.sudo-rs.wheelNeedsPassword = false;
  security.pam.services.login.enableKwallet = true;
  # fscrypt for home folder encryption
  security.pam.enableFscrypt = true;
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "10000";
    }
  ];

  # Disable man page cache generation since it's very slow and fish enable it by default
  documentation.man.generateCaches = false;
}
