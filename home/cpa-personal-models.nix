# Personal (xAI login) models served by CLIProxyAPI under the "personal/" prefix,
# generated from CLIProxyAPI's bundled model registry.
{
  lib,
  catalog,
}: let
  prefix = "personal/";
  defaultId = "grok-4.7";
  smallId = "grok-4.7-build-fast";

  models =
    builtins.filter (m: m.supportedOutputModalities or [] == ["text"])
    (builtins.fromJSON (builtins.readFile catalog)).xai;
  ids = map (m: m.id) models;

  efforts = m: m.thinking.levels or null;
  images = m: builtins.elem "image" (m.supportedInputModalities or []);

  quote = s: ''"${s}"'';
  toGrokToml = m:
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
in
  assert lib.assertMsg (builtins.elem defaultId ids && builtins.elem smallId ids)
  "cpa-personal-models: ${defaultId} or ${smallId} missing from ${catalog}"; {
    defaultModelId = prefix + defaultId;
    smallModelId = prefix + smallId;

    grokConfigModelsToml = lib.concatMapStrings toGrokToml models;

    opencodeModels = builtins.listToAttrs (map (m: {
        name = prefix + m.id;
        value = {
          name = m.display_name;
          limit = {
            context = m.context_length;
            output = m.max_completion_tokens;
          };
        };
      })
      models);

    zedAvailableModels = map (m:
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
          chat_completions = false;
          interleaved_reasoning = false;
          max_tokens_parameter = false;
        };
      }
      // lib.optionalAttrs (efforts m != null) {reasoning_effort = "high";})
    models;
  }
