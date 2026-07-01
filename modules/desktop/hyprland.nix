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
    ];

    # Set the menu prefix so kbuildsycoca6 knows to look for plasma-applications.menu
    environment.sessionVariables = {
      XDG_MENU_PREFIX = "plasma-";
    };

    # This fixes the unpopulated MIME menus in kde applications
    environment.etc."/xdg/menus/plasma-applications.menu".text =
      builtins.readFile "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

    programs.dms-shell = {
      enable = true;
      systemd = {
        enable = true;
        restartIfChanged = true;
      };
      enableClipboardPaste = true;
      plugins =
        {
          dankBitwarden.enable = true;
          dankSpotify.enable = true;
          dankTranslate.enable = true;
          canvasGrades.enable = true;
          dmsScreenshot.enable = true;
          dockerManager.enable = true;
          easyEffects.enable = true;
          githubNotifier.enable = true;
          nixPackageRunner.enable = true;
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

    environment.systemPackages = with pkgs; [
      jq
      ncspot
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
