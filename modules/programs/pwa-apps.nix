{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dreaming.programs.pwaApps;

  # A PWA "app": a native browser window (Brave `--app=`) that shares the normal browser profile.
  mkPwaApp = {
    name,
    url,
    desktopName,
    icon ? name,
    iconFile ? null,
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
      inherit
        name
        desktopName
        icon
        categories
        ;
      exec = "${name} %U";
      terminal = false;
      startupWMClass = name;
    };

    # Install a single SVG logo into the hicolor theme as the launcher icon.
    # Built natively (just a copy) so apps whose upstream package has no build
    # for this host don't force an emulated build just to supply an icon.
    iconPkg = pkgs.runCommand "${name}-pwa-icon" {} ''
      dir="$out/share/icons/hicolor/scalable/apps"
      mkdir -p "$dir"
      cp ${iconFile} "$dir/${icon}.svg"
    '';
  in
    pkgs.symlinkJoin {
      name = "${name}-pwa";
      paths =
        [
          launcher
          desktopItem
        ]
        ++ lib.optional (iconFile != null) iconPkg;
    };
in {
  options.dreaming.programs.pwaApps = {
    enable = lib.mkEnableOption "native browser PWA app launchers";

    browser = lib.mkOption {
      type = lib.types.str;
      default = "brave";
      description = "Browser command used to open PWA windows (must support --app=).";
    };

    apps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
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
            iconFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "An SVG image installed into the hicolor theme as the launcher icon.";
            };
            categories = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = ["Network"];
              description = "Freedesktop categories for the desktop entry.";
            };
          };
        }
      );
      default = [];
      description = "PWA apps to install as native browser launchers.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      map (
        app:
          mkPwaApp {
            inherit
              (app)
              name
              url
              desktopName
              iconFile
              categories
              ;
            icon =
              if app.icon == ""
              then app.name
              else app.icon;
          }
      )
      cfg.apps;
  };
}
