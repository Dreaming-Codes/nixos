# Paneru: scrollable-tiling window manager for macOS (PaperWM/niri-style).
# Bindings mirror the niri config (config/niri/dms/binds.kdl) as closely as the
# macOS/paneru model allows. niri's `Mod` (Super) maps to `alt` here to avoid
# clashing with macOS system `cmd` shortcuts.
#
# Notes on what does NOT translate:
#   * Spawn binds (browser/terminal/launcher) are niri compositor concerns;
#     paneru only manages windows, so those stay in niri-land.
#   * niri's per-monitor directional focus has no direct paneru equivalent;
#     paneru exposes next-display cycling instead.
{
  services.paneru = {
    enable = true;

    settings = {
      options = {
        # niri: input { focus-follows-mouse; warp-mouse-to-focus center-xy }
        focus_follows_mouse = true;
        mouse_follows_focus = true;
        # niri cycles preset column widths with Mod+R; same ratios as upstream.
        preset_column_widths = [
          0.25
          0.33
          0.5
          0.66
          0.75
        ];
        # niri centers the focused column; mirror that feel on focus change.
        auto_center = true;
        animation_speed = 12.0;
        # Closest analogue to niri's incremental width/height resize (Mod+Minus/
        # Equal): hold alt+shift and drag — the window edge nearest the cursor
        # follows the pointer. Paneru has no keybound +/-10% or vertical resize,
        # and resize is modifier+motion (no mouse-button gating exists).
        mouse_resize_modifier = "alt + shift";
      };

      # niri layout { gaps 4 } -> uniform screen padding.
      padding = {
        top = 4;
        bottom = 4;
        left = 4;
        right = 4;
      };

      # niri scroll binds: Mod+WheelScroll{Left,Right} slides the strip; on macOS
      # hold alt + scroll to slide windows horizontally, alt+shift to change rows.
      # `continuous = false` makes the swipe snap to columns (niri-like) instead
      # of free-scrolling smoothly with the fingers.
      swipe = {
        continuous = false;
        scroll = {
          modifier = "alt";
          vertical_modifier = "shift";
        };
      };

      bindings = {
        # ── Column / window focus ────────────────────────────────
        # niri: Mod+H/Left focus-column-left, Mod+L/Right focus-column-right
        window_focus_west = [ "alt - h" "alt - leftarrow" ];
        window_focus_east = [ "alt - l" "alt - rightarrow" ];
        # niri: Mod+K/Up focus-window-up, Mod+J/Down focus-window-down
        window_focus_north = [ "alt - k" "alt - uparrow" ];
        window_focus_south = [ "alt - j" "alt - downarrow" ];

        # ── Move / swap windows ──────────────────────────────────
        # niri: Mod+Shift+H/Left move-column-left, Mod+Shift+L/Right move-column-right
        window_swap_west = [ "alt + shift - h" "alt + shift - leftarrow" ];
        window_swap_east = [ "alt + shift - l" "alt + shift - rightarrow" ];
        # niri: Mod+Shift+K/Up move-window-up, Mod+Shift+J/Down move-window-down
        window_swap_north = [ "alt + shift - k" "alt + shift - uparrow" ];
        window_swap_south = [ "alt + shift - j" "alt + shift - downarrow" ];

        # ── Sizing ───────────────────────────────────────────────
        # niri: Mod+R switch-preset-column-width
        window_resize = "alt - r";
        # niri: Mod+Shift+R switch-preset-window-height (no direct paneru action;
        # closest is shrinking the preset width cycle).
        window_shrink = "alt + shift - r";
        # niri: Mod+Shift+F maximize-column / Mod+Ctrl+F expand-to-available-width
        window_fullwidth = "alt + shift - f";
        # paneru-native: re-center current window in the viewport.
        window_center = "alt - c";

        # ── Floating / state ─────────────────────────────────────
        # niri: Mod+O toggle-window-floating
        window_manage = "alt - o";

        # ── Displays ─────────────────────────────────────────────
        # niri: Mod+Ctrl+arrows focus-monitor-* (paneru cycles to next display)
        window_nextdisplay = "alt + ctrl - rightarrow";
        # niri: Mod+Shift+Ctrl+arrows move-column-to-monitor-* (send + follow)
        window_nextdisplaysend = "alt + shift + ctrl - rightarrow";
        mouse_nextdisplay = "alt + ctrl - leftarrow";

        # ── Virtual workspaces (niri vertical workspaces) ────────
        # niri: Mod+U/PageDown focus-workspace-down, Mod+I/PageUp focus-workspace-up
        window_virtual_south = "alt - u";
        window_virtual_north = "alt - i";
        # niri: Mod+Ctrl+U/PageDown move-column-to-workspace-down (and up)
        window_virtualmove_south = "alt + ctrl - u";
        window_virtualmove_north = "alt + ctrl - i";

        # niri: Mod+1..0 focus-workspace N
        window_virtualnum_1 = "alt - 1";
        window_virtualnum_2 = "alt - 2";
        window_virtualnum_3 = "alt - 3";
        window_virtualnum_4 = "alt - 4";
        window_virtualnum_5 = "alt - 5";
        window_virtualnum_6 = "alt - 6";
        window_virtualnum_7 = "alt - 7";
        window_virtualnum_8 = "alt - 8";
        window_virtualnum_9 = "alt - 9";
        window_virtualnum_10 = "alt - 0";

        # niri: Mod+Shift+1..0 move-column-to-workspace N (and follow)
        window_virtualmovenum_1 = "alt + shift - 1";
        window_virtualmovenum_2 = "alt + shift - 2";
        window_virtualmovenum_3 = "alt + shift - 3";
        window_virtualmovenum_4 = "alt + shift - 4";
        window_virtualmovenum_5 = "alt + shift - 5";
        window_virtualmovenum_6 = "alt + shift - 6";
        window_virtualmovenum_7 = "alt + shift - 7";
        window_virtualmovenum_8 = "alt + shift - 8";
        window_virtualmovenum_9 = "alt + shift - 9";
        window_virtualmovenum_10 = "alt + shift - 0";

        # ── Session ──────────────────────────────────────────────
        # niri: Mod+Shift+E quit
        quit = "alt + shift - e";
      };
    };
  };
}
