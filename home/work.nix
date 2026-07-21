{
  config,
  lib,
  pkgs,
  ...
}: let
  wallpaper = ../config/wallpaper/neuralink-4k.png;
  wallpaperDest = "${config.home.homeDirectory}/Pictures/neuralink-4k.png";
in {
  # BedrockAccess (AWS) + xAI. API key comes from XAI_API_KEY via the work
  # sops template (environment.d/90-xai.conf); Zed reads that env var natively.
  # Linux already has zed-editor in systemPackages; only manage settings here.
  # Darwin still installs via HM (package left at the option default).
  programs.zed-editor = {
    enable = true;
    package = lib.mkIf pkgs.stdenv.isLinux null;
    # Helix theme = "transparent" inherits material_darker syntax but clears
    # ui.background, so the real bg is Rio (#141218 / #e6e0e9) — not #212121.
    # nix extension so alejandra can format Nix buffers (helix languages.toml).
    extensions = [
      "material-theme"
      "nix"
    ];
    userSettings = {
      # Enables Helix keybindings (and vim mode as a dependency).
      helix_mode = true;
      # Match Rio terminal (config/rio/config.toml).
      buffer_font_family = "IoskeleyMono Nerd Font";
      ui_font_family = "IoskeleyMono Nerd Font";
      buffer_line_height = "standard";
      # Helix config.toml: line-number = "relative"
      relative_line_numbers = "enabled";
      # Helix cursor-shape: insert=bar, normal=block, select=underline
      # (select → visual in Zed's vim/helix mode).
      vim.cursor_shape = {
        normal = "block";
        insert = "bar";
        visual = "underline";
      };
      # LSP semantic tokens on top of tree-sitter highlighting.
      semantic_tokens = "combined";
      diagnostics.inline.enabled = true;
      use_smartcase_search = true;
      close_on_file_delete = true;
      # Pretend we're already in Zellij so shell hooks don't nest it in Zed.
      terminal.env.ZELLIJ = "1";
      terminal.font_family = "IoskeleyMono Nerd Font";
      git.inline_blame.location = "status_bar";
      # Project tree left; agent/chat right.
      agent.dock = "right";
      project_panel.dock = "left";
      # Turn off OS-level agent terminal/fetch sandboxing.
      agent.sandbox_permissions.allow_unsandboxed = true;
      # OpenCode-style permissions: allow everything, but ask on push/PR/MR/tf.
      agent.tool_permissions = {
        default = "allow";
        tools.terminal = {
          default = "allow";
          always_confirm = [
            {pattern = ''git\s+push(\s|$)'';}
            {pattern = ''gh\s+pr\s+(create|edit|merge|close)(\s|$)'';}
            {pattern = ''glab\s+mr\s+(create|update|merge|close)(\s|$)'';}
            {pattern = ''terraform\s+(apply|destroy|import)'';}
          ];
        };
      };
      # No agent feedback/thread sharing, no edit-prediction training, no telemetry.
      agent.enable_feedback = false;
      agent.show_turn_stats = true;
      edit_predictions.allow_data_collection = "no";
      telemetry = {
        diagnostics = false;
        metrics = false;
        # Keep off (already default) so Anthropic non-ZDR models are not used.
        anthropic_retention = false;
      };
      # Material Darker syntax + Rio terminal surface (what Helix actually shows).
      # Default Material Darker comments/muted/line numbers are nearly unreadable.
      theme = "Material Theme Darker";
      theme_overrides."Material Theme Darker" = {
        "background.appearance" = "opaque";
        # Rio config/rio/config.toml
        background = "#141218";
        "editor.background" = "#141218";
        "editor.gutter.background" = "#141218";
        "panel.background" = "#141218";
        "tab_bar.background" = "#141218";
        "tab.inactive_background" = "#141218";
        "tab.active_background" = "#1e1b24";
        "status_bar.background" = "#141218";
        "title_bar.background" = "#141218";
        "title_bar.inactive_background" = "#141218";
        "toolbar.background" = "#141218";
        "surface.background" = "#141218";
        "elevated_surface.background" = "#1e1b24";
        "element.background" = "#1e1b24";
        "element.hover" = "#2a2633";
        "element.selected" = "#323232";
        "terminal.background" = "#141218";
        "terminal.foreground" = "#e6e0e9";
        # Helix material_darker text + Rio default fg for UI chrome
        "editor.foreground" = "#b0bec5";
        text = "#e6e0e9";
        "text.muted" = "#90a4ae";
        "text.placeholder" = "#78909c";
        "text.disabled" = "#616161";
        "editor.line_number" = "#616161";
        "editor.active_line_number" = "#ff9800";
        "editor.active_line.background" = "#1e1b24";
        border = "#2a2633";
        "border.variant" = "#323232";
        # Stock Material Darker comments are #545454 — unreadable on dark UI.
        syntax.comment = {
          color = "#78909c";
          font_style = "italic";
        };
        syntax."comment.doc" = {
          color = "#78909c";
          font_style = "italic";
        };
      };
      language_models = {
        bedrock = {
          authentication_method = "named_profile";
          region = "us-west-2";
          profile = "BedrockAccess";
        };
        # Builtin xAI list stops at 4.3 / 4.20; add 4.5 until Zed ships it.
        x_ai.available_models = [
          {
            name = "grok-4.5";
            display_name = "Grok 4.5";
            max_tokens = 500000;
            max_output_tokens = 500000;
            supports_tools = true;
            supports_images = true;
            parallel_tool_calls = true;
          }
        ];
      };
      agent.default_model = {
        provider = "x_ai";
        model = "grok-4.5";
      };
      # Helix :reload reloads the buffer; Zed has no such colon cmd, so the
      # palette fuzzy-matches workspace::Reload (app restart). Alias to file reload.
      # (:e / :edit already map to editor::ReloadFile in vim/helix mode.)
      command_aliases = {
        reload = "editor::ReloadFile";
        "reload!" = "editor::ReloadFile";
      };
      # External ACP agents (registry ids match the ACP registry).
      agent_servers = {
        opencode.type = "registry";
        "grok-build".type = "registry";
        "claude-acp".type = "registry";
        "codex-acp".type = "registry";
      };
      # Only non-default bits from config/helix/languages.toml.
      lsp."rust-analyzer".initialization_options.check.command = "clippy";
      languages.Nix = {
        format_on_save = "on";
        formatter.external = {
          command = "alejandra";
          arguments = [
            "--quiet"
            "-"
          ];
        };
      };
    };
    # Mirror config/helix/config.toml leader maps (space …), adapted for Zed.
    # With helix_mode, modes are helix_normal / helix_select (not normal/visual).
    # shared: project/agent chords (editor + agent UI).
    # terminalShared: same under ctrl-space (plain Space stays free for the shell).
    # bufferLocal: need a focused file buffer (editor only).
    #
    # Multi-key chord timeout (GPUI, hardcoded ~1s):
    # - Editor/helix normal: fixed by unbinding bare `space` (was also
    #   vim::WrappingRight). With only incomplete multi-key matches, Zed waits
    #   until the chord finishes or Escape — no timer.
    # - Terminal: still times out. Terminal always has a text InputHandler, and
    #   GPUI forces a 1s flush whenever a pending keystroke has a key_char and
    #   the focused view accepts text input — even with no complete binding for
    #   the prefix. Unbinding ctrl-space cannot fix that; needs an upstream
    #   setting (e.g. keybinding_timeout_ms). See:
    #   https://github.com/zed-industries/zed/discussions/28576
    userKeymaps = let
      shared = {
        # space g c: helix changed_file_picker analogue (project uncommitted diff).
        "space g c" = "git::Diff";
        # space g g: gitui floating -> Zed git panel
        "space g g" = "git_panel::ToggleFocus";
        "space i t" = "multi_workspace::FocusWorkspaceSidebar";
        "space i a" = "agent::ToggleFocus";
        # First center pane is the code editor (agent is docked right).
        "space i c" = [
          "workspace::ActivatePane"
          0
        ];
      };
      # Same chords under ctrl-space so terminals keep a free Space for typing.
      # Chords work if completed within GPUI's ~1s pending timeout (see above).
      terminalShared = {
        # Avoid a complete single-key ctrl-space binding competing with chords
        # (same idea as nulling bare space in helix). Does not remove the
        # terminal text-input 1s flush — see discussion 28576.
        "ctrl-space" = null;
        "ctrl-space g c" = "git::Diff";
        "ctrl-space g g" = "git_panel::ToggleFocus";
        "ctrl-space i t" = "multi_workspace::FocusWorkspaceSidebar";
        "ctrl-space i a" = "agent::ToggleFocus";
        "ctrl-space i c" = [
          "workspace::ActivatePane"
          0
        ];
      };
      bufferLocal = {
        # space e: file explorer for current buffer
        "space e" = "pane::RevealInProjectPanel";
        # space c / C — copy path, or path:line / path:start-end
        "space c" = "workspace::CopyPath";
        "space shift-c" = "editor::CopyFileLocation";
      };
      agentOrEditor =
        "(AgentPanel || ThreadsSidebar || ThreadHistory || ThreadSwitcher || AcpThread)"
        + " && !Terminal && (!(Editor) || vim_mode == helix_normal || vim_mode == helix_select) && !menu";
    in [
      {
        # Unbind bare space so multi-key "space …" chords do not share a complete
        # single-key binding (vim::WrappingRight). See discussion 28576 for the
        # missing configurable timeout; this is the helix-shaped workaround.
        # https://github.com/zed-industries/zed/discussions/28576
        context = "(vim_mode == helix_normal || vim_mode == helix_select) && !menu";
        bindings = {
          space = null;
        };
      }
      {
        context = "Editor && (vim_mode == helix_normal || vim_mode == helix_select) && !menu";
        bindings = bufferLocal // shared;
      }
      {
        # No buffer open: the Editor context above never matches, so route
        # space e to the pane directly. pane::RevealInProjectPanel falls back
        # to focusing the project panel when there is no file to reveal.
        context = "EmptyPane && !menu";
        bindings = {
          "space e" = "pane::RevealInProjectPanel";
        };
      }
      {
        # Agent UI: project/agent chords only (no current-buffer actions).
        context = agentOrEditor;
        bindings = shared // {space = null;};
      }
      {
        # Zed terminals + agent-embedded terminals (AgentPanel > Terminal).
        context = "Terminal";
        bindings = terminalShared;
      }
      {
        # Helix insert: C-space → completion (editor only; not Terminal)
        context = "Editor && vim_mode == insert && !menu";
        bindings = {
          "ctrl-space" = "editor::ShowCompletions";
        };
      }
    ];
  };

  home.file.".config/nixos-local-aws/config".source = ../config/aws/work.config;

  home.file."Pictures/neuralink-4k.png".source = wallpaper;

  home.sessionVariables = {
    AWS_CONFIG_FILE = "${config.home.homeDirectory}/.config/nixos-local-aws/config";
    AWS_PROFILE = "BedrockAccess";
    AWS_REGION = "us-west-2";
  };

  # Pin wallpaper on work hosts. Runs after dmsDefaults (when present) so the
  # merge of shared session defaults cannot override the work path.
  home.activation.setWorkWallpaper = lib.hm.dag.entryAfter ["writeBoundary" "dmsDefaults"] ''
    wallpaper="${wallpaperDest}"
    session="$HOME/.local/state/DankMaterialShell/session.json"

    if [ -f "$session" ]; then
      tmp="$(mktemp)"
      if ${pkgs.jq}/bin/jq \
        --arg path "$wallpaper" \
        '.wallpaperPath = $path | .wallpaperCyclingEnabled = false' \
        "$session" > "$tmp"
      then
        mv "$tmp" "$session"
      else
        rm -f "$tmp"
      fi
    fi

    # Live session: DMS on Linux work hosts (niri).
    if command -v dms >/dev/null 2>&1; then
      dms ipc call wallpaper set "$wallpaper" >/dev/null 2>&1 || true
    fi

    # DreamingNeuraBook (darwin) has no DMS; set the desktop picture directly.
    if [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
      osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$wallpaper\"" >/dev/null 2>&1 || true
    fi
  '';
}
