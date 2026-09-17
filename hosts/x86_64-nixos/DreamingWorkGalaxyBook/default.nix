{
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./disk-config.nix
    ./display-profiles.nix
    ./ish-firmware.nix
    ./ambient-light.nix
  ];

  # Samsung Galaxy Book6 Ultra (Panther Lake).
  # Hardware report: hosts/x86_64-nixos/DreamingWorkGalaxyBook/facter.json
  # (wired via flake-modules/hosts.nix). Regenerate with:
  #   sudo nixos-facter -o hosts/x86_64-nixos/DreamingWorkGalaxyBook/facter.json

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.loader.limine.efiInstallAsRemovable = lib.mkForce true;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.limine.secureBoot.enable = true;
  environment.systemPackages = [pkgs.sbctl];

  # Intel Arc B390 iGPU only, no dGPU.
  hardware.graphics.enable = true;

  # Webcam is Intel IPU7 (no nixpkgs support yet) and the fingerprint reader is
  # an Egis sensor needing a patched libfprint, so neither is configured.

  # FDE is the boot gate: skip greeter password after LUKS unlock.
  # dms-greeter implements this via greetd initial_session.
  services.displayManager.autoLogin = {
    enable = true;
    user = "dreamingcodes";
  };

  # niri enables gnome-keyring by default; this host uses KWallet as the
  # Secret portal, and autologin cannot unlock a login-password keyring.
  services.gnome.gnome-keyring.enable = lib.mkForce false;

  # Empty-password KWallet (set on disk already). LUKS covers secrets at rest
  home-manager.users.dreamingcodes = {
    xdg.configFile."kwalletrc".text = ''
      [Wallet]
      Close When Unused=false
      Enabled=true
      First Use=false
      Leave Open=true
      Prompt on Open=false
    '';
  };
}
