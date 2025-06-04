{
  pkgs,
  config,
  lib,
  niri,
  ...
}: let
  inherit (niri.lib.kdl) node plain leaf flag;
in {
  home-manager.users.dreamingcodes.programs.niri.settings = {
    input = {
      keyboard = {
        xkb = {
          layout = "us";
          variant = "intl";
        };
        # TODO: missing waiting for PR https://github.com/sodiboo/niri-flake/pull/1068
        # numlock = true;
      };
      touchpad = {
        tap = true;
        natural-scroll = true;
      };
      focus-follows-mouse = {
        enable = true;
      };
      warp-mouse-to-focus = true;
    };

    environment."DISPLAY" = ":0";

    layout = {
      gaps = 0;
    };

    screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

    spawn-at-startup = [
      {command = ["clipcatd --no-daemon --replace"];}
      {command = ["xwayland-satellite"];}
    ];

    hotkey-overlay = {
      # skip-at-startup = true;
    };

    window-rules = [
      {
        matches = [
          {
            app-id = "firefox$";
            title = "^Picture-in-Picture$";
          }
        ];
        open-floating = true;
      }
    ];

    binds = {
      "Mod+Shift+Slash".action.show-hotkey-overlay = [];
      "Mod+Space" = {
        hotkey-overlay = {
          title = "Open a Terminal";
        };
        action.spawn = ["wezterm"];
      };
      "Mod+W" = {
        hotkey-overlay = {
          title = "Open browser";
        };
        action.spawn = ["google-chrome-stable"];
      };
      "Mod+X" = {
        hotkey-overlay = {
          title = "Application launcher";
        };
        action.spawn = ["anyrun"];
      };
      "XF86AudioRaiseVolume".action.spawn = [
        "wpctl"
        "set-volume"
        "@DEFAULT_AUDIO_SINK@"
        "0.1+"
      ];
      "XF86AudioLowerVolume".action.spawn = [
        "wpctl"
        "set-volume"
        "@DEFAULT_AUDIO_SINK@"
        "0.1-"
      ];
      "Mod+Q".action.close-window = [];
      "Mod+Left".action.focus-column-left = [];
      "Mod+Down".action.focus-window-down = [];
      "Mod+Up".action.focus-window-up = [];
      "Mod+Right".action.focus-column-right = [];
      "Mod+H".action.focus-column-left = [];
      "Mod+J".action.focus-window-down = [];
      "Mod+K".action.focus-window-up = [];
      "Mod+L".action.focus-column-right = [];
      "Mod+O".action.toggle-overview = [];
      "Mod+Ctrl+Left".action.move-column-left = [];
      "Mod+Ctrl+Down".action.move-window-down = [];
      "Mod+Ctrl+Up".action.move-window-up = [];
      "Mod+Ctrl+Right".action.move-column-right = [];
      "Mod+Ctrl+H".action.move-column-left = [];
      "Mod+Ctrl+J".action.move-window-down = [];
      "Mod+Ctrl+K".action.move-window-up = [];
      "Mod+Ctrl+L".action.move-column-right = [];
      "Mod+Home".action.focus-column-first = [];
      "Mod+End".action.focus-column-last = [];
      "Mod+Ctrl+Home".action.move-column-to-first = [];
      "Mod+Ctrl+End".action.move-column-to-last = [];
      "Mod+Shift+Left".action.focus-monitor-left = [];
      "Mod+Shift+Down".action.focus-monitor-down = [];
      "Mod+Shift+Up".action.focus-monitor-up = [];
      "Mod+Shift+Right".action.focus-monitor-right = [];
      "Mod+Shift+H".action.focus-monitor-left = [];
      "Mod+Shift+J".action.focus-monitor-down = [];
      "Mod+Shift+K".action.focus-monitor-up = [];
      "Mod+Shift+L".action.focus-monitor-right = [];
      "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [];
      "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [];
      "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [];
      "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [];
      "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = [];
      "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = [];
      "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = [];
      "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = [];
      "Mod+Page_Down".action.focus-workspace-down = [];
      "Mod+Page_Up".action.focus-workspace-up = [];
      "Mod+U".action.focus-workspace-down = [];
      "Mod+I".action.focus-workspace-up = [];
      "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = [];
      "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = [];
      "Mod+Ctrl+U".action.move-column-to-workspace-down = [];
      "Mod+Ctrl+I".action.move-column-to-workspace-up = [];
      "Mod+Shift+Page_Down".action.move-workspace-down = [];
      "Mod+Shift+Page_Up".action.move-workspace-up = [];
      "Mod+Shift+U".action.move-workspace-down = [];
      "Mod+Shift+I".action.move-workspace-up = [];
      "Mod+1".action.focus-workspace = [1];
      "Mod+2".action.focus-workspace = [2];
      "Mod+3".action.focus-workspace = [3];
      "Mod+4".action.focus-workspace = [4];
      "Mod+5".action.focus-workspace = [5];
      "Mod+6".action.focus-workspace = [6];
      "Mod+7".action.focus-workspace = [7];
      "Mod+8".action.focus-workspace = [8];
      "Mod+9".action.focus-workspace = [9];
      "Mod+Ctrl+1".action.move-column-to-workspace = [1];
      "Mod+Ctrl+2".action.move-column-to-workspace = [2];
      "Mod+Ctrl+3".action.move-column-to-workspace = [3];
      "Mod+Ctrl+4".action.move-column-to-workspace = [4];
      "Mod+Ctrl+5".action.move-column-to-workspace = [5];
      "Mod+Ctrl+6".action.move-column-to-workspace = [6];
      "Mod+Ctrl+7".action.move-column-to-workspace = [7];
      "Mod+Ctrl+8".action.move-column-to-workspace = [8];
      "Mod+Ctrl+9".action.move-column-to-workspace = [9];
      "Mod+Comma".action.consume-window-into-column = [];
      "Mod+Period".action.expel-window-from-column = [];
      "Mod+R".action.switch-preset-column-width = [];
      "Mod+F".action.maximize-column = [];
      "Mod+Shift+F".action.fullscreen-window = [];
      "Mod+C".action.center-column = [];
      "Mod+Minus".action.set-column-width = ["-10%"];
      "Mod+Equal".action.set-column-width = ["+10%"];
      "Mod+Shift+Minus".action.set-window-height = ["-10%"];
      "Mod+Shift+Equal".action.set-window-height = ["+10%"];
      "Print".action.screenshot = [];
      "Ctrl+Print".action.screenshot-screen = [];
      "Alt+Print".action.screenshot-window = [];
      "Mod+Shift+E".action.quit = [];
      "Mod+Shift+P".action.power-off-monitors = [];
    };

    debug = {
      # dbus-interfaces-in-non-session-instances = true;
      # wait-for-frame-completion-before-queueing = true;
      # enable-overlay-planes = true;
      # disable-cursor-plane = true;
      # render-drm-device = "/dev/dri/renderD129";
      # enable-color-transformations-capability = true;
      # emulate-zero-presentation-time = true;
    };
  };
}
