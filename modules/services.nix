{
  config,
  pkgs,
  inputs,
  ...
}: {
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

  services.printing = {
    enable = true;
    drivers = [
      pkgs.hplipWithPlugin
    ];
  };

  # Centralized storage for coredumps (coredumpctl list)
  systemd.coredump.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    systemWide = false;
    wireplumber.enable = true;
  };

  virtualisation = {
    docker.enable = true;
    spiceUSBRedirection.enable = true;
  };

  environment.etc = {
    # https://github.com/Scrut1ny/Hypervisor-Phantom
    "ovmf" = {
      source = ./ovmf;
    };
  };
}
