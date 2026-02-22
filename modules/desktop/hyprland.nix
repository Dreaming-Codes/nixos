{pkgs, ...}: {
  services.envfs.enable = true;

  services.xserver.enable = true;

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  # Default session for dreamingcodes (and system-wide fallback)
  services.displayManager.defaultSession = "hyprland";

  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    konsole
    kate
    elisa
    krdp
    plasma-browser-integration
  ];

  # Set the menu prefix so kbuildsycoca6 knows to look for plasma-applications.menu
  environment.sessionVariables = {
    XDG_MENU_PREFIX = "plasma-";
  };

  # This fixes the unpopulated MIME menus in kde applications
  environment.etc."/xdg/menus/plasma-applications.menu".text =
    builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

  programs.hyprland = {
    enable = true;
  };
  programs.hyprlock.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "alt-intl";
  };

  # Centralized storage for coredumps (coredumpctl list)
  systemd.coredump.enable = true;

  # dconf needed for GTK apps and virt-manager
  programs.dconf.enable = true;

  environment.etc = {
    # https://github.com/Scrut1ny/Hypervisor-Phantom
    "ovmf" = {
      source = ../../config/ovmf;
    };
  };
}
