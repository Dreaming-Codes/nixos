{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.desktop.hyprland;
in {
  options.dreaming.desktop.hyprland.enable =
    lib.mkEnableOption "Hyprland compositor"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    services.xserver.enable = true;

    services.displayManager.dms-greeter = {
      enable = true;
      compositor.name = "niri";
      configHome = "/home/dreamingcodes";
    };
    # Default session for dreamingcodes (and system-wide fallback)
    services.displayManager.defaultSession = "niri";

    services.desktopManager.plasma6.enable = true;
    environment.plasma6.excludePackages = with pkgs.kdePackages; [
      konsole
      kate
      elisa
      krdp
      plasma-browser-integration
      plasma-workspace-wallpapers
      qrca
    ];
    programs.kde-pim.merkuro = false;

    # Set the menu prefix so kbuildsycoca6 knows to look for plasma-applications.menu
    environment.sessionVariables = {
      XDG_MENU_PREFIX = "plasma-";
    };

    # This fixes the unpopulated MIME menus in kde applications
    environment.etc."/xdg/menus/plasma-applications.menu".text =
      builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

    programs.dms-shell = {
      enable = true;
      # Lock-screen fprint PAM defaults to max-tries=5 and timeout=30s, so the
      # sensor stops listening after a short idle on the lock screen. Negative
      # values keep verify armed for the whole lock session (see pam_fprintd(8)).
      package = pkgs.dms-shell;
      systemd = {
        enable = true;
        target = "niri.service";
        restartIfChanged = true;
      };
      plugins =
        {
          dankBitwarden.enable = true;
          dankTranslate.enable = true;
          dmsScreenshot.enable = true;
          dockerManager.enable = true;
          easyEffects.enable = true;
          volumeMixer.enable = true;
        }
        // lib.optionalAttrs (config.networking.hostName == "DreamingBlade") {
          RazerEnergy = {
            enable = true;
            src = ../../config/dms-plugins/RazerEnergy;
          };
        };
    };

    systemd.user.services.dms.environment = let
      qt5CompatQmlPath = "${pkgs.qt6.qt5compat}/lib/qt-6/qml";
    in {
      QML2_IMPORT_PATH = qt5CompatQmlPath;
      QML_IMPORT_PATH = qt5CompatQmlPath;
      QT_QPA_PLATFORMTHEME = "kde";
      QT_QPA_PLATFORMTHEME_QT6 = "kde";
      GTK_THEME = "adw-gtk3-dark";
      DMS_DEFAULT_LAUNCH_PREFIX = "systemd-run --user --scope --collect --same-dir";
    };

    # authtok_pin: pam_u2f takes the PIN from the password pam_unix rejected,
    # so the lock screen field accepts either with one entry.
    nixpkgs.overlays = [
      (final: prev: {
        pam_u2f = prev.pam_u2f.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./pam_u2f-authtok-pin.patch];
        });
        # Keep-awake/idle inhibit blocks lock+suspend, but still allows monitor-off
        # (including post-lock). Upstream gated all idle timers on inhibit.
        dux-shell = prev.dux-shell.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./dux-shell-idle-inhibit-allow-monitor-off.patch];
        });
        dms-shell = final.dux-shell;
      })
    ];

    # Security key goes in the primary lock stack because DMS answers its PIN
    # prompt from the password field there. DMS runs fingerprint separately.
    # Shared origin so one root-owned key file works on every host.
    security.pam.u2f.settings = {
      authfile = "${../../config/u2f_keys}";
      origin = "pam://dreaming";
      appid = "pam://dreaming";
      authtok_pin = true;
      cue = true;
      pinverification = 1;
    };
    # Key after password: a typed password sent as the PIN costs a key PIN retry.
    security.pam.services.dankshell = {
      u2f.enable = true;
      fprintAuth = false;
      rules.auth.u2f.order = config.security.pam.services.dankshell.rules.auth.unix.order + 10;
    };

    environment.systemPackages = with pkgs; [
      jq
      ncspot
      pam_u2f
      qt6.qt5compat
      rbw
      translate-shell
    ];

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
  };
}
