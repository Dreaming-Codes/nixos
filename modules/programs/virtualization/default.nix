{
  config,
  pkgs,
  ...
}: {
  imports = [
    # ./edk2.nix
    ./libvirt.nix
    ./qemu
    ./looking_glass
    ./kernel.nix
  ];

  programs = {
    dconf.enable = true;
    virt-manager.enable = true;
  };

  environment.systemPackages = with pkgs; [
    spice
    spice-gtk
    spice-protocol
    virt-manager
    virt-viewer
    virtio-win
    win-spice
    virtiofsd
  ];

  virtualisation.spiceUSBRedirection.enable = true;
  services.spice-vdagentd.enable = true;
}
