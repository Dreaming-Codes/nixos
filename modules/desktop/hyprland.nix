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
  environment.plasma6.excludePackages = with pkgs.kdePackages; [konsole];

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
