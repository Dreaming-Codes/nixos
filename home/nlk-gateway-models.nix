# Build OpenCode / Zed / Grok model configs from git-crypt'd secrets/work/:
#   1. ai-gateway-models.json           ← GET …/v1/models
#   2. ai-gateway-model-info.json       ← GET …/v1/model/info
#   3. ai-gateway-team-overrides.json   ← Neuralink Grok managed_config
#      (only when the catalog omits context_window / name)
#
# Alias ids that share a LiteLLM upstream collapse to one picker entry.
# Team keys ending in -extended fold onto the base id (Grok's 200k/500k
# split is a CLI pin, not a second gateway model).
# Grok Build: work.nix activation rewrites [model.*] in ~/.grok/config.toml
# from grokConfigModelsToml (picker slugs → catalog limits).
# Refresh catalog: scripts/update-ai-gateway-models.sh
{lib}: let
  modelsFile = ../secrets/work/ai-gateway-models.json;
  infoFile = ../secrets/work/ai-gateway-model-info.json;
  teamFile = ../secrets/work/ai-gateway-team-overrides.json;

  modelsJson = builtins.fromJSON (builtins.readFile modelsFile);
  infoJson = builtins.fromJSON (builtins.readFile infoFile);
  teamJson = builtins.fromJSON (builtins.readFile teamFile);

  # Prefer *-extended limits; drop the 200k sibling and the -extended key.
  teamModels = let
    raw = teamJson.models;
    extendedKeys = builtins.filter (k: lib.hasSuffix "-extended" k) (builtins.attrNames raw);
    fold = acc: extKey: let
      base = lib.removeSuffix "-extended" extKey;
      ext = raw.${extKey};
      prev = acc.${base} or {};
      stripped =
        if (ext.name or null) != null
        then builtins.replaceStrings [" Extended"] [""] ext.name
        else null;
      name = prev.name or stripped;
    in
      acc
      // {
        ${base} = ext // lib.optionalAttrs (name != null) {inherit name;};
      };
  in
    builtins.removeAttrs (lib.foldl' fold raw extendedKeys) extendedKeys;
  providerDefaultContext = teamJson.provider_default_context_window;

  modelsById = builtins.listToAttrs (
    map (m: {
      name = m.id;
      value = m;
    })
    modelsJson.data
  );

  infoRows =
    map (
      e: let
        mi = e.model_info or {};
        lp = e.litellm_params or {};
      in {
        id = e.model_name;
        upstream = lp.model or e.model_name;
        max_input_tokens = mi.max_input_tokens or null;
        max_output_tokens = mi.max_output_tokens or null;
        max_tokens = mi.max_tokens or null;
        mode = mi.mode or null;
        tools = mi.supports_function_calling or null;
        vision = mi.supports_vision or null;
        reasoning = mi.supports_reasoning or null;
        caching = mi.supports_prompt_caching or null;
        parallel = mi.supports_parallel_function_calling or null;
      }
    )
    infoJson.data;

  infoIds = lib.listToAttrs (
    map (r: {
      name = r.id;
      value = true;
    })
    infoRows
  );

  modelsOnlyRows =
    map (
      m: {
        id = m.id;
        upstream = m.id;
        max_input_tokens = m.max_input_tokens or null;
        max_output_tokens = m.max_output_tokens or null;
        max_tokens = null;
        mode = null;
        tools = null;
        vision = null;
        reasoning = null;
        caching = null;
        parallel = null;
      }
    )
    (
      builtins.filter (m: !(infoIds ? ${m.id})) modelsJson.data
    );

  allRows = infoRows ++ modelsOnlyRows;

  rankId = id: let
    has = needle: lib.hasInfix needle id;
    starts = prefix: lib.hasPrefix prefix id;
    penalty =
      (lib.optional (has "[1m]") (-10000))
      ++ (lib.optional (has "fallback") (-5000))
      ++ (lib.optional (has "preview") (-20))
      ++ (lib.optional (starts "us.") (-100))
      ++ (lib.optional (!has "." && !has "-") (-200))
      ++ (lib.optional (starts "openai.") (-10));
    bonus =
      (lib.optional (starts "global.") 200)
      ++ [(builtins.stringLength id)]
      ++ (lib.optional (has "-") 15);
  in
    lib.foldl' builtins.add 0 (penalty ++ bonus);

  byUpstream = lib.groupBy (r: r.upstream) allRows;

  catalogField = rows: bestId: field: let
    fromRows = lib.findFirst (r: r.${field} != null) null rows;
    fromModels = (modelsById.${bestId} or {}).${field} or null;
  in
    if fromRows != null && fromRows.${field} != null
    then fromRows.${field}
    else fromModels;

  # First team override matching any alias id in the group.
  teamFor = aliasIds:
    lib.findFirst (id: teamModels ? ${id}) null aliasIds;

  pickGroup = _upstream: rows: let
    sorted = lib.sort (a: b: rankId a.id > rankId b.id) rows;
    best = builtins.head sorted;
    aliasIds = map (r: r.id) rows;
    field = catalogField rows best.id;

    teamKey = teamFor aliasIds;
    team = lib.optionalAttrs (teamKey != null) teamModels.${teamKey};

    catalogIn = field "max_input_tokens";
    catalogOut = let
      out = field "max_output_tokens";
      mt = field "max_tokens";
    in
      if out != null
      then out
      else mt;

    # API first; else team context_window; else provider default if team lists the model.
    max_input_tokens =
      if catalogIn != null
      then catalogIn
      else if team ? context_window
      then team.context_window
      else if teamKey != null
      then providerDefaultContext
      else null;

    # API first; else team max_output_tokens; else same as context (input).
    # Zed shows 0 if max_output_tokens is missing entirely.
    max_output_tokens = let
      teamOut = team.max_output_tokens or null;
      # max_input may still be null here; resolved after both are known.
      raw =
        if catalogOut != null
        then catalogOut
        else if teamOut != null
        then teamOut
        else null;
    in
      raw;

    catalogMode = field "mode";
    # Prefer catalog mode; else map team api_backend.
    mode =
      if catalogMode != null
      then catalogMode
      else if (team.api_backend or null) == "messages"
      then "chat"
      else if (team.api_backend or null) == "chat_completions"
      then "chat"
      else null;

    # Caps: catalog first, else team override (null stays null until toZed).
    pickCap = catalogVal: teamAttr:
      if catalogVal != null
      then catalogVal
      else if team ? ${teamAttr}
      then team.${teamAttr}
      else null;
  in {
    id = best.id;
    aliases = aliasIds;
    inherit mode max_input_tokens;
    # If still null after catalog+team, mirror context window once known.
    max_output_tokens =
      if max_output_tokens != null
      then max_output_tokens
      else max_input_tokens;
    tools = pickCap (field "tools") "tools";
    vision = pickCap (field "vision") "vision";
    reasoning = pickCap (field "reasoning") "reasoning";
    caching = field "caching";
    parallel = field "parallel";
    reasoning_effort = team.reasoning_effort or null;
    reasoning_efforts = team.reasoning_efforts or null;
    # Team display name when present; else derived from id later.
    teamName = team.name or null;
    fromTeamLimits = catalogIn == null && max_input_tokens != null;
  };

  resolvedUnsorted = lib.mapAttrsToList pickGroup byUpstream;

  # Keep rows with a context size from API or team hardcodes.
  resolvedWithLimits =
    builtins.filter (r: r.max_input_tokens != null) resolvedUnsorted;

  familyRank = id:
    if lib.hasPrefix "global.anthropic." id
    then 0
    else if lib.hasPrefix "global." id
    then 1
    else if lib.hasPrefix "claude" id || lib.hasPrefix "grok" id || lib.hasPrefix "gpt" id
    then 2
    else if lib.hasPrefix "gemini" id
    then 3
    else 4;

  resolved =
    lib.sort (
      a: b:
        if familyRank a.id != familyRank b.id
        then familyRank a.id < familyRank b.id
        else a.id < b.id
    )
    resolvedWithLimits;

  displayOf = r: let
    strip = prefixes: s:
      lib.foldl' (
        acc: p:
          if lib.hasPrefix p acc
          then lib.removePrefix p acc
          else acc
      )
      s
      prefixes;
  in
    if r.teamName != null
    then r.teamName
    else strip ["global.anthropic." "us.anthropic." "openai." "global."] r.id;

  cap = v: v != null && v;

  toOpencodeModel = r:
    {
      name = displayOf r;
    }
    // lib.optionalAttrs true {
      limit =
        {context = r.max_input_tokens;}
        // lib.optionalAttrs (r.max_output_tokens != null) {
          output = r.max_output_tokens;
        };
    };

  toZedModel = r: let
    supportsReasoning = cap r.reasoning;
    # Responses-API models (GPT via mantle): chat_completions=false.
    # Chat models with reasoning: enable interleaved thinking stream.
    useResponses = r.mode == "responses";
  in
    {
      name = r.id;
      display_name = displayOf r;
      max_tokens = r.max_input_tokens;
      # Always set — omitting this makes Zed UI show output limit 0.
      max_output_tokens =
        if r.max_output_tokens != null
        then r.max_output_tokens
        else r.max_input_tokens;
      capabilities = {
        tools =
          if r.tools == null
          then true
          else r.tools;
        images = cap r.vision;
        parallel_tool_calls =
          if r.parallel == null
          then true
          else r.parallel;
        prompt_cache_key = cap r.caching;
        chat_completions = !useResponses;
        interleaved_reasoning = supportsReasoning && !useResponses;
        max_tokens_parameter = false;
      };
    }
    # Zed: non-none reasoning_effort enables thinking UI / effort control.
    // lib.optionalAttrs supportsReasoning {
      reasoning_effort =
        if r.reasoning_effort != null
        then r.reasoning_effort
        else "high";
    };

  defaultModelId = let
    opuses =
      builtins.filter (
        r: lib.hasPrefix "global.anthropic.claude-opus" r.id
      )
      resolved;
    sortedOpus = lib.sort (a: b: a.id < b.id) opuses;
  in
    if sortedOpus != []
    then (lib.last sortedOpus).id
    else (builtins.head resolved).id;

  # Lookup resolved row by any catalog alias id in its upstream group.
  resolvedByAlias = lib.listToAttrs (
    lib.concatMap (
      r:
        map (a: {
          name = a;
          value = r;
        })
        (lib.unique ([r.id] ++ r.aliases))
    )
    resolved
  );

  # Grok Build picker ids (managed version_overrides keys) → gateway catalog id.
  # Limits come from resolved; slug is what config.toml [model.<id>] must use.
  grokManagedSlugs = {
    "claude-sonnet-gateway" = "global.anthropic.claude-sonnet-5";
    "claude-opus-gateway" = "global.anthropic.claude-opus-5";
    "claude-haiku-gateway" = "global.anthropic.claude-haiku-4-5-20251001-v1:0";
    "claude-sonnet-4-6-gateway" = "global.anthropic.claude-sonnet-4-6";
    "claude-opus-4-7-gateway" = "global.anthropic.claude-opus-4-7";
    "fable-gateway" = "global.anthropic.claude-fable-5";
    "gpt-5-6-sol-gateway" = "openai.gpt-5.6-sol";
    "gpt-5-6-luna-gateway" = "openai.gpt-5.6-luna";
    "gpt-5-6-terra-gateway" = "openai.gpt-5.6-terra";
    "grok-4.5" = "grok-4.5";
    "grok-4.6" = "grok-4.6";
    "grok-4.6-extended" = "grok-4.6";
  };

  tomlModelKey = id:
    if builtins.match "[A-Za-z0-9_-]+" id != null
    then id
    else ''"${id}"'';

  toGrokModelToml = slug: r: let
    out =
      if r.max_output_tokens != null
      then r.max_output_tokens
      else r.max_input_tokens;
  in ''
    [model.${tomlModelKey slug}]
    context_window = ${toString r.max_input_tokens}
    max_completion_tokens = ${toString out}
  '';

  grokConfigModelsToml = let
    slugs = lib.sort (a: b: a < b) (builtins.attrNames grokManagedSlugs);
    parts =
      map (
        slug: let
          catalogId = grokManagedSlugs.${slug};
          r = resolvedByAlias.${catalogId} or null;
        in
          if r == null
          then ""
          else toGrokModelToml slug r
      )
      slugs;
  in
    lib.concatStrings parts;
in {
  apiUrl = "https://ai-gateway.svc.int.n7k.io/v1";

  inherit defaultModelId resolved grokConfigModelsToml;

  skippedNoLimits =
    map (r: r.id)
    (
      builtins.filter (r: r.max_input_tokens == null) resolvedUnsorted
    );

  opencodeModels = builtins.listToAttrs (
    map (r: {
      name = r.id;
      value = toOpencodeModel r;
    })
    resolved
  );

  zedAvailableModels = map toZedModel resolved;
}
