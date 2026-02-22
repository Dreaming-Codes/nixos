{pkgs, ...}: {
  services.envfs.enable = true;

  # Fix FUSE race condition where mount.envfs returns before the kernel
  # registers the mount, causing systemd to report "Failed to mount /usr/bin"
  # and the subsequent deps /bin
  fileSystems."/usr/bin".options = ["x-systemd.mount-timeout=10s"];
  fileSystems."/bin".options = ["x-systemd.mount-timeout=10s"];

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
