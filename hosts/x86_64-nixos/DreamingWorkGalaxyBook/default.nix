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
  boot.kernelParams = ["fsck.repair=yes"];
  environment.systemPackages = [pkgs.sbctl];

  dreaming.core.cryptroot-fido-or-pass.enable = true;

  # Intel Arc B390 iGPU only, no dGPU. iHD VA-API for hw decode/encode.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [intel-media-driver];
    extraPackages32 = with pkgs.pkgsi686Linux; [intel-media-driver];
  };

  # IPU7 + SC200PC (SSLC2000); see modules/hardware/galaxybook6-camera.nix.
  dreaming.hardware.galaxybook6-camera.enable = true;

  # Copilot key -> Meta; see modules/hardware/galaxybook6-keys.nix.
  dreaming.hardware.galaxybook6-keys.enable = true;

  # Fingerprint: EGIS ETU906Axx-E (1c7a:05d5). Chip list/enroll returns
  # storage errors (list 65 fe, enroll-mode 91 00) under stock egismoc; needs
  # likeablob ETU906 SDCP fork (Joshua Grisham SDCP-v2 + 05b1) plus 05d5.
  # https://github.com/likeablob/libfprint-fmv-etu906axx-e
  nixpkgs.overlays = [
    (final: prev: {
      libfprint = prev.libfprint.overrideAttrs (old: {
        version = "1.94.9-etu906axx-sdcp-05d5";
        src = prev.fetchFromGitHub {
          owner = "likeablob";
          repo = "libfprint-fmv-etu906axx-e";
          rev = "e105528828a04dffde789cda48742c204183386d";
          hash = "sha256-Hp5as35tfzTO57uAwN9FsXp7dS23gb7TaCHrYDab74w=";
        };
        patches = [./libfprint-egismoc-1c7a-05d5-sdcp.patch];
        postPatch = ''
          # SDCP fork tests need GI/umockdev at configure; keep vars for examples.
          cat > tests/meson.build <<'EOF'
          installed_tests = get_option('installed-tests')
          installed_tests_execdir = libexecdir / 'installed-tests' / versioned_libname
          installed_tests_testdir = datadir / 'installed-tests' / versioned_libname
          installed_tests_libdir = libdir
          EOF
        '';
        mesonFlags = (old.mesonFlags or []) ++ ["-Dinstalled-tests=false"];
        doCheck = false;
        doInstallCheck = false;
      });
    })
  ];
  services.fprintd.enable = true;

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
