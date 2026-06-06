{
  pkgs,
  ...
}: let
  waydroid = pkgs.waydroid.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        substituteInPlace $out/lib/waydroid/tools/services/clipboard_manager.py \
          --replace-fail 'return pyclip.paste()' 'return pyclip.paste(text=True)'
      '';
  });
in {
  virtualisation.waydroid = {
    enable = true;
    package = waydroid;
  };

  systemd.services.waydroid-container = {
    path = [pkgs.lxc];
    preStart = ''
      cfg=/var/lib/waydroid/waydroid.cfg
      if [ -f "$cfg" ]; then
        if ${pkgs.gnugrep}/bin/grep -q '^suspend_action = ' "$cfg"; then
          ${pkgs.gnused}/bin/sed -i 's/^suspend_action = .*/suspend_action = freeze/' "$cfg"
        else
          ${pkgs.gnused}/bin/sed -i '/^\[waydroid\]/a suspend_action = freeze' "$cfg"
        fi
      fi
    '';
    serviceConfig.Delegate = true;
  };

  systemd.services.bpftune.serviceConfig.PrivateMounts = true;
}
