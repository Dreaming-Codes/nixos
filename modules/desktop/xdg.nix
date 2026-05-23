{
  lib,
  pkgs,
  ...
}: {
  # System-wide MIME associations to ensure consistency with portal usage
  xdg.mime = {
    enable = true;
    defaultApplications = {
      "application/pdf" = "brave-origin-nightly.desktop";
      "x-scheme-handler/http" = "brave-origin-nightly.desktop";
      "x-scheme-handler/https" = "brave-origin-nightly.desktop";
      "text/html" = "brave-origin-nightly.desktop";
    };
  };

  xdg.portal = {
    xdgOpenUsePortal = true;
    enable = true;

    config = {
      hyprland = {
        default = [
          "hyprland"
          "gtk"
          "kde"
        ];
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
      };
      niri = lib.mkForce {
        default = [
          "gnome"
          "gtk"
          "kde"
        ];
        "org.freedesktop.impl.portal.Access" = "gtk";
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.Notification" = "gtk";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
        "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
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
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gnome
      # Add xdg-desktop-portal-gtk for Wayland GTK apps (font issues etc.)
      xdg-desktop-portal-gtk
      kdePackages.xdg-desktop-portal-kde
    ];
  };
}
