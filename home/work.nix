{
  config,
  lib,
  pkgs,
  ...
}: let
  wallpaper = ../config/wallpaper/neuralink-4k.png;
  wallpaperDest = "${config.home.homeDirectory}/Pictures/neuralink-4k.png";

  # Model lists generated from git-crypt'd gateway catalog dumps.
  gatewayModels = import ./nlk-gateway-models.nix {
    inherit lib;
    cpaCatalog = cpa.registryFile;
  };
  # Same catalog as seen by clients through CLIProxyAPI.
  workModels = import ./nlk-gateway-models.nix {
    inherit lib;
    modelPrefix = "work/";
    grokProvider = "cli-proxy-api";
  };
  cpa = config.dreaming.cliProxyApi;

  claudeWorkSettings = pkgs.writeText "claude-work-settings.json" (builtins.toJSON {
    apiKeyHelper = "${pkgs.coreutils}/bin/cat ${cpa.keyFile}";
    env = {
      ANTHROPIC_BASE_URL = cpa.url;
      ANTHROPIC_DEFAULT_OPUS_MODEL = "work/global.anthropic.claude-opus-5-5";
      ANTHROPIC_DEFAULT_SONNET_MODEL = "work/global.anthropic.claude-sonnet-5-5";
      ANTHROPIC_DEFAULT_HAIKU_MODEL = "work/global.anthropic.claude-haiku-5-5";
    };
  });

  nlk-llm-proxy = pkgs.writeShellApplication {
    name = "nlk-llm-proxy";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
    ];
    text = builtins.replaceStrings ["@llm_proxy_py@"] ["${../secrets/work/llm_proxy.py}"] (
      builtins.readFile ./nlk-llm-proxy.sh
    );
  };

  yq = "${pkgs.yq-go}/bin/yq";
  cpaGatewayProviders = pkgs.writeText "cpa-nlk-gateway.json" (builtins.toJSON {
    openai-compatibility = {
      name = "nlk-gateway";
      prefix = "work";
      base-url = gatewayModels.apiUrl;
      models = gatewayModels.cliProxyApiModels;
    };
    # Native Anthropic passthrough keeps thinking signatures intact.
    claude = {
      name = "nlk-gateway";
      prefix = "work";
      base-url = lib.removeSuffix "/v1" gatewayModels.apiUrl;
      models = gatewayModels.cliProxyApiClaudeModels;
    };
  });

  xaiWorkPriority = 1;

  # Gateway id_tokens live ~65 min and `auth` only renews near expiry, so this
  # runs every few minutes. CLIProxyAPI hot-reloads config.yaml on change.
  cpaGatewaySync = pkgs.writeShellScript "cli-proxy-api-nlk-gateway-sync" ''
    set -euo pipefail
    umask 077
    config="$HOME/.cli-proxy-api/config.yaml"
    shopt -s nullglob
    for auth in "$HOME/.cli-proxy-api"/xai-*.json; do
      prefix="$(${pkgs.jq}/bin/jq -r '.prefix // ""' "$auth")"
      [ "$prefix" = "work" ] || continue
      have="$(${pkgs.jq}/bin/jq -r '.priority // 0' "$auth")"
      [ "$have" = "${toString xaiWorkPriority}" ] && continue
      tmp="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.jq}/bin/jq '.priority = ${toString xaiWorkPriority}' "$auth" > "$tmp"
      ${pkgs.coreutils}/bin/chmod --reference="$auth" "$tmp"
      ${pkgs.coreutils}/bin/mv "$tmp" "$auth"
    done

    key="$(${nlk-llm-proxy}/bin/nlk-llm-proxy auth)"

    entries="$(${pkgs.coreutils}/bin/mktemp)"
    trap 'rm -f "$entries"' EXIT
    ${pkgs.jq}/bin/jq -S --arg k "$key" 'map_values(. + {keys: [{"api-key": $k}]}) | .claude.keys[0].cloak.mode = "never"' ${cpaGatewayProviders} > "$entries"

    current="$(${yq} -o=json '.api-keys | with_entries(select(.key == "openai-compatibility" or .key == "claude")) | map_values([.[] | select(.name == "nlk-gateway")][0])' "$config" | ${pkgs.jq}/bin/jq -S .)"
    [ "$current" = "$(cat "$entries")" ] && exit 0

    ENTRIES="$entries" ${yq} -i '
      load(strenv(ENTRIES)) as $e |
      .api-keys."openai-compatibility" = ([(.api-keys."openai-compatibility" // [])[] | select(.name != "nlk-gateway")] + [$e."openai-compatibility"]) |
      .api-keys.claude = ([(.api-keys.claude // [])[] | select(.name != "nlk-gateway")] + [$e.claude])
    ' "$config"
  '';
in {
  home.packages = [
    nlk-llm-proxy
  ];

  systemd.user.services.cli-proxy-api-nlk-gateway = {
    Unit = {
      Description = "Sync Neuralink AI gateway token into CLIProxyAPI";
      After = ["cli-proxy-api.service"];
      ConditionPathExists = "%h/.cli-proxy-api/config.yaml";
    };
    Install.WantedBy = ["cli-proxy-api.service"];
    Service = {
      Type = "oneshot";
      ExecStart = "${cpaGatewaySync}";
    };
  };

  systemd.user.timers.cli-proxy-api-nlk-gateway = {
    Unit.Description = "Refresh Neuralink AI gateway token in CLIProxyAPI";
    Install.WantedBy = ["timers.target"];
    Timer = {
      OnActiveSec = "1min";
      OnUnitActiveSec = "4min";
    };
  };

  # Stock OpenCode binary (cli.nix); work models go through CLIProxyAPI.
  programs.opencode.settings = {
    enabled_providers = ["cpa-work"];
    provider.cpa-work = {
      npm = "@ai-sdk/openai-compatible";
      name = "CLIProxyAPI work";
      options = {
        baseURL = "${cpa.url}/v1";
        apiKey = "{file:${cpa.keyFile}}";
      };
      models = workModels.opencodeModels;
    };
    model = lib.mkDefault "cpa-work/work/${gatewayModels.defaultModelId}";
  };

  dreaming.cliProxyApi.grokModels = workModels.grokConfigModelsToml;
  dreaming.cliProxyApi.codexModel = "work/${gatewayModels.defaultModelId}";

  # Merge work routing into Claude Code's mutable user settings.
  home.activation.claudeCliProxyApi = lib.hm.dag.entryAfter ["writeBoundary"] ''
    settings="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    [ -s "$settings" ] || echo '{}' > "$settings"
    tmp="$(${pkgs.coreutils}/bin/mktemp)"
    ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$settings" ${claudeWorkSettings} > "$tmp"
    ${pkgs.coreutils}/bin/mv "$tmp" "$settings"
  '';

  # Stock zed from the system profile. Reads CPA_WORK_API_KEY and
  # CPA_PERSONAL_API_KEY, which cli-proxy-api writes into environment.d.
  programs.zed-editor = {
    enable = true;
    package = null;
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
      buffer_font_family = "IoskeleyMono Nerd Font Mono";
      ui_font_family = "IoskeleyMono Nerd Font Mono";
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
      terminal.font_family = "IoskeleyMono Nerd Font Mono";
      git.inline_blame.location = "status_bar";
      git.worktree_directory = "~/Documents/worktrees";
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
      language_models.openai_compatible = {
        cpa-work = {
          api_url = "${cpa.url}/v1";
          available_models = workModels.zedAvailableModels;
        };
        cpa-personal = {
          api_url = "${cpa.url}/v1";
          available_models = cpa.personalModels.zedAvailableModels;
        };
      };
      agent.default_model = {
        # Nested key under language_models.openai_compatible.
        provider = "cpa-work";
        model = "work/${gatewayModels.defaultModelId}";
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

  home.file."Pictures/neuralink-4k.png".source = wallpaper;

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
  '';
}
