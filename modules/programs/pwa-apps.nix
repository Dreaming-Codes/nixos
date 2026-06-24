{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.pwaApps;

  # A PWA "app": a native browser window (Brave `--app=`) that shares the normal browser profile.
  mkPwaApp = {
    name,
    url,
    desktopName,
    icon ? name,
    iconSource ? null,
    categories ? ["Network"],
  }: let
    launcher = pkgs.writeShellApplication {
      inherit name;
      text = ''
        exec ${cfg.browser} \
          --app=${lib.escapeShellArg url} \
          --class=${lib.escapeShellArg name} \
          --name=${lib.escapeShellArg name} \
          "$@"
      '';
    };

    desktopItem = pkgs.makeDesktopItem {
      inherit name desktopName icon categories;
      exec = "${name} %U";
      terminal = false;
      startupWMClass = name;
    };

    # Copy only the icon tree out of iconSource. The resulting derivation's
    # runtime closure is just the icon files, so iconSource is a build-time
    # input and is not pulled into the system closure.
    iconPkg = pkgs.runCommand "${name}-pwa-icon" {} ''
      mkdir -p "$out/share"
      if [ -d "${iconSource}/share/icons" ]; then
        cp -R --no-preserve=mode,ownership "${iconSource}/share/icons" "$out/share/"
      fi
    '';
  in
    pkgs.symlinkJoin {
      name = "${name}-pwa";
      paths = [launcher desktopItem] ++ lib.optional (iconSource != null) iconPkg;
    };
in {
  options.programs.pwaApps = {
    enable = lib.mkEnableOption "native browser PWA app launchers";

    browser = lib.mkOption {
      type = lib.types.str;
      default = "brave";
      description = "Browser command used to open PWA windows (must support --app=).";
    };

    apps = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Launcher command and window class.";
          };
          url = lib.mkOption {
            type = lib.types.str;
            description = "URL the PWA opens.";
          };
          desktopName = lib.mkOption {
            type = lib.types.str;
            description = "Display name shown in the app launcher.";
          };
          icon = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Icon name for the desktop entry (defaults to name).";
          };
          iconSource = lib.mkOption {
            type = lib.types.nullOr lib.types.package;
            default = null;
            description = "Package whose share/icons tree provides the launcher icon.";
          };
          categories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = ["Network"];
            description = "Freedesktop categories for the desktop entry.";
          };
        };
      });
      default = [];
      description = "PWA apps to install as native browser launchers.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = map (app:
      mkPwaApp {
        inherit (app) name url desktopName iconSource categories;
        icon =
          if app.icon == ""
          then app.name
          else app.icon;
      })
    cfg.apps;
  };
}
