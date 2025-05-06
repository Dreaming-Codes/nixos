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
  services.desktopManager.plasma6.enable = true;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [konsole];

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    portalPackage = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
  };
  programs.hyprlock.enable = true;
  services.hypridle.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "alt-intl";
  };

  services.printing.enable = true;

  # Centralized storage for coredumps (coredumpctl list)
  systemd.coredump.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  virtualisation = {
    docker.enable = true;
    libvirtd = {
      enable = true;

      onShutdown = "suspend";
      onBoot = "ignore";

      qemu = {
        package = pkgs.qemu_kvm.overrideAttrs (attrs: {
          # https://github.com/lixiaoliu666/pve-anti-detection
          patches = attrs.patches ++ [./qemu-autoGenPatch.patch];
        });
        swtpm.enable = true;
        ovmf.enable = false;
      };
    };
    spiceUSBRedirection.enable = true;
  };

  environment.etc = {
    # https://github.com/Scrut1ny/Hypervisor-Phantom
    "ovmf" = {
      source = ./ovmf;
    };
  };
}
