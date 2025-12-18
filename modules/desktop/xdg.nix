{pkgs, ...}: {
  xdg.portal = {
    xdgOpenUsePortal = true;
    enable = true;

    config = {
      hyprland = {
        default = ["hyprland" "gtk" "kde"];
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
      };
      plasma = {
        default = ["kde" "gtk"];
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.OpenURI" = "kde";
      };
    };

    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      # Add xdg-desktop-portal-gtk for Wayland GTK apps (font issues etc.)
      xdg-desktop-portal-gtk
      kdePackages.xdg-desktop-portal-kde
    ];
  };
}
