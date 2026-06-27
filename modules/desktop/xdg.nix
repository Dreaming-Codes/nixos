{
  lib,
  pkgs,
  ...
}: {
  # System-wide MIME associations to ensure consistency with portal usage
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "application/pdf" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "text/html" = "brave-browser.desktop";
    };
  };

  xdg.portal = {
    xdgOpenUsePortal = true;
    enable = true;

    config = {
      niri = lib.mkForce {
        default = [
          "gnome"
          "gtk"
          "kwallet"
          "kde"
        ];
        "org.freedesktop.impl.portal.Access" = "gtk";
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.Notification" = "gtk";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
        "org.freedesktop.impl.portal.Secret" = "kwallet";
      };
      plasma = {
        default = [
          "kde"
          "gtk"
        ];
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
      };
    };

    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      # Add xdg-desktop-portal-gtk for Wayland GTK apps (font issues etc.)
      xdg-desktop-portal-gtk
      kdePackages.kwallet
      kdePackages.xdg-desktop-portal-kde
    ];
  };
}
