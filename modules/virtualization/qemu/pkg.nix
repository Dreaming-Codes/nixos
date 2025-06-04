{pkgs, ...}: let
  patchedOverlay = import ./overlay.nix;
in {
  nixpkgs.overlays = [patchedOverlay];
  virtualisation.libvirtd = {
    qemu = {
      package = pkgs.qemu;
    };
  };

  environment.etc = {
    spoofedQemu = {
      source = pkgs.patched-qemu;
    };
  };

  environment.systemPackages = [pkgs.qemu pkgs.patched-qemu];
}
