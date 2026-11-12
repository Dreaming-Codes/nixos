# Personal models served by CLIProxyAPI under the "personal/" prefix,
# generated from CLIProxyAPI's bundled model registry.
# xAI logins speak the responses API. A Claude OAuth login speaks messages.
{
  lib,
  catalog,
}: let
  prefix = "personal/";
  defaultId = "grok-4.7";
  smallId = "grok-4.7-build-fast";

  catalogJson = builtins.fromJSON (builtins.readFile catalog);
  # Claude 3.5 Haiku omits modalities; every other chat row is ["text"].
  textOut = m: let
    outs = m.supportedOutputModalities or null;
  in
    outs == null || outs == ["text"];
  xai =
    builtins.filter (m: m.supportedOutputModalities or [] == ["text"])
    catalogJson.xai;
  claude = builtins.filter textOut (catalogJson.claude or []);
  models = xai ++ claude;
  ids = map (m: m.id) xai;
  claudeIds = map (m: m.id) claude;
  # Same generation as the work Claude Code slots.
  claudeModel = name:
    assert lib.assertMsg (builtins.elem name claudeIds)
    "cpa-personal-models: ${name} missing from ${catalog}";
      prefix + name;

  efforts = m: m.thinking.levels or null;
  images = m: builtins.elem "image" (m.supportedInputModalities or []);
  hasThinking = m: (m.thinking or null) != null;
  # grok-4.20-0309-reasoning has no thinking object in the registry.
  reasons = m:
    hasThinking m
    || (lib.hasInfix "reasoning" m.id && !lib.hasInfix "non-reasoning" m.id);

  quote = s: ''"${s}"'';
  toXaiGrokToml = m:
    lib.concatStringsSep "\n" (
      [
        "[model.${quote "personal-${m.id}"}]"
        "model = ${quote (prefix + m.id)}"
        "name = ${quote "${m.display_name} (personal)"}"
        "model_provider = \"cli-proxy-api\""
        "api_backend = \"responses\""
        "context_window = ${toString m.context_length}"
        "max_completion_tokens = ${toString m.max_completion_tokens}"
        "system_prompt_label = ${quote m.display_name}"
      ]
      ++ lib.optional (m.native_capabilities.web_search or false) "supports_backend_search = true"
      ++ lib.optionals (efforts m != null) [
        "supports_reasoning_effort = true"
        "reasoning_efforts = [${lib.concatMapStringsSep ", " quote (efforts m)}]"
      ]
    )
    + "\n";

  # messages keeps thinking signatures. OpenAI-compat translation drops them.
  toClaudeGrokToml = m:
    lib.concatStringsSep "\n" (
      [
        "[model.${quote "personal-${m.id}"}]"
        "model = ${quote (prefix + m.id)}"
        "name = ${quote "${m.display_name} (personal)"}"
        "model_provider = \"cli-proxy-api\""
        "api_backend = \"messages\""
        "context_window = ${toString m.context_length}"
        "max_completion_tokens = ${toString m.max_completion_tokens}"
      ]
      ++ lib.optionals (efforts m != null) [
        "supports_reasoning_effort = true"
        "reasoning_efforts = [${lib.concatMapStringsSep ", " quote (efforts m)}]"
      ]
      ++ lib.optional (efforts m == null && hasThinking m) "reasoning_effort = \"high\""
      ++ [
        ""
        "[model.${quote "personal-${m.id}"}.extra_headers]"
        "anthropic-version = \"2023-06-01\""
      ]
    )
    + "\n";

  toOpencode = m: {
    name = prefix + m.id;
    value =
      {
        name = m.display_name;
        limit = {
          context = m.context_length;
          output = m.max_completion_tokens;
        };
      }
      # OpenAI-compatible variants default to low/medium/high.
      // lib.optionalAttrs (efforts m != null) {
        capabilities.reasoning = {
          supported = true;
          effort = efforts m;
        };
      }
      # CPA returns reasoning text only when the chat request asks for a summary.
      // lib.optionalAttrs (reasons m) {
        body.include_reasoning = true;
      };
  };

  toZed = chatCompletions: m:
    {
      name = prefix + m.id;
      display_name = "${m.display_name} (personal)";
      max_tokens = m.context_length;
      max_output_tokens = m.max_completion_tokens;
      capabilities = {
        tools = true;
        images = images m;
        parallel_tool_calls = true;
        prompt_cache_key = false;
        chat_completions = chatCompletions;
        interleaved_reasoning = chatCompletions && hasThinking m;
        max_tokens_parameter = false;
      };
    }
    // lib.optionalAttrs (efforts m != null || (chatCompletions && hasThinking m)) {
      reasoning_effort = "high";
    };
in
  assert lib.assertMsg (builtins.elem defaultId ids && builtins.elem smallId ids)
  "cpa-personal-models: ${defaultId} or ${smallId} missing from ${catalog}";
  assert lib.assertMsg (claude != [])
  "cpa-personal-models: no claude models in ${catalog}"; {
    defaultModelId = prefix + defaultId;
    smallModelId = prefix + smallId;
    claudeOpusModelId = claudeModel "claude-opus-5-5";
    claudeSonnetModelId = claudeModel "claude-sonnet-5-5";
    claudeHaikuModelId = claudeModel "claude-haiku-5-5";

    grokConfigModelsToml =
      lib.concatMapStrings toXaiGrokToml xai
      + lib.concatMapStrings toClaudeGrokToml claude;

    opencodeModels = builtins.listToAttrs (map toOpencode models);

    zedAvailableModels = map (toZed false) xai ++ map (toZed true) claude;
  }
