# OpenCode / Zed / Grok model lists from git-crypt'd secrets/work/:
#   1. ai-gateway-models.json          GET /v1/models
#   2. ai-gateway-model-info.json      GET /v1/model/info
#   3. ai-gateway-team-overrides.json  caps when the catalog omits them
#
# Ids that share a LiteLLM upstream collapse to one picker row.
# Team keys ending in -extended fold onto the base id (Grok 200k vs 500k is a
# CLI pin on one gateway model).
# work.nix writes grokConfigModelsToml as [model.*] into ~/.grok/config.toml.
# Refresh: scripts/update-ai-gateway-models.sh
{lib}: let
  modelsFile = ../secrets/work/ai-gateway-models.json;
  infoFile = ../secrets/work/ai-gateway-model-info.json;
  teamFile = ../secrets/work/ai-gateway-team-overrides.json;

  modelsJson = builtins.fromJSON (builtins.readFile modelsFile);
  infoJson = builtins.fromJSON (builtins.readFile infoFile);
  teamJson = builtins.fromJSON (builtins.readFile teamFile);

  # Fold *-extended team keys onto the base id; keep the larger window.
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

    # catalog max_input_tokens, else team.context_window, else provider default.
    max_input_tokens =
      if catalogIn != null
      then catalogIn
      else if team ? context_window
      then team.context_window
      else if teamKey != null
      then providerDefaultContext
      else null;

    # catalog max_output_tokens / max_tokens, else team; null filled below.
    max_output_tokens = let
      teamOut = team.max_output_tokens or null;
      raw =
        if catalogOut != null
        then catalogOut
        else if teamOut != null
        then teamOut
        else null;
    in
      raw;

    catalogMode = field "mode";
    # catalog mode, else chat when team.api_backend is messages or chat_completions.
    mode =
      if catalogMode != null
      then catalogMode
      else if (team.api_backend or null) == "messages"
      then "chat"
      else if (team.api_backend or null) == "chat_completions"
      then "chat"
      else null;

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
    api_backend = team.api_backend or null;
    teamName = team.name or null;
    # Override key hit by teamFor; used as wire id when no managed slug.
    teamKey = teamKey;
    fromTeamLimits = catalogIn == null && max_input_tokens != null;
  };

  resolvedUnsorted = lib.mapAttrsToList pickGroup byUpstream;

  # Drop rows with no context size from catalog or team.
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
    # mode == responses => chat_completions false (GPT mantle).
    useResponses = r.mode == "responses";
  in
    {
      name = r.id;
      display_name = displayOf r;
      max_tokens = r.max_input_tokens;
      # Zed shows output limit 0 if this field is missing.
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
    # reasoning_effort turns on Zed thinking UI for reasoning models.
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

  # managed_config version_overrides key -> catalog wire id.
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

  # Same wire model; picker context_window only (managed_config pins).
  grokContextPin = {
    "grok-4.6" = 200000;
    "grok-4.6-extended" = 500000;
  };

  grokExtendedName = {
    "grok-4.6-extended" = "Grok 4.6 Extended (AI Gateway)";
  };

  tomlModelKey = id:
    if builtins.match "[A-Za-z0-9_-]+" id != null
    then id
    else ''"${id}"'';

  tomlString = s: let
    esc = builtins.replaceStrings ["\\" "\""] ["\\\\" "\\\""] s;
  in ''"${esc}"'';

  tomlStringArray = xs: let
    body = lib.concatStringsSep ",\n    " (map tomlString xs);
  in "[\n    ${body},\n]";

  isAnthropicId = id:
    (lib.hasInfix "anthropic" id)
    || (lib.hasPrefix "claude" id)
    || (lib.hasInfix "fable" id);

  isGrokId = id: lib.hasPrefix "grok" id;

  # Grok agent path uses responses (managed_config). Anthropic uses messages.
  # Otherwise team.api_backend, then catalog mode, else chat_completions.
  grokApiBackend = r:
    if isGrokId r.id
    then "responses"
    else if isAnthropicId r.id
    then "messages"
    else if (r.api_backend or null) != null
    then r.api_backend
    else if r.mode == "responses"
    then "responses"
    else "chat_completions";

  # managed slug if this row is in grokManagedSlugs, else catalog id.
  grokSlugFor = r: let
    matching =
      lib.filterAttrs (
        slug: cid:
          cid == r.id || builtins.elem cid r.aliases
      )
      grokManagedSlugs;
    nonExt =
      lib.filterAttrs (slug: _: !(lib.hasSuffix "-extended" slug)) matching;
    pick = attrs:
      if attrs == {}
      then null
      else builtins.head (lib.sort (a: b: a < b) (builtins.attrNames attrs));
    fromNonExt = pick nonExt;
    fromAny = pick matching;
  in
    if fromNonExt != null
    then fromNonExt
    else if fromAny != null
    then fromAny
    else r.id;

  # Request model id: managed map, else teamKey, else ranked catalog id.
  grokWireModel = slug: r:
    if grokManagedSlugs ? ${slug}
    then grokManagedSlugs.${slug}
    else if (r.teamKey or null) != null
    then r.teamKey
    else r.id;

  # system_prompt_label for Grok rows (extended keeps the base label).
  grokSystemLabel = slug: wire: display:
    if grokExtendedName ? ${slug}
    then "Grok 4.6"
    else if isGrokId wire
    then lib.removeSuffix " (AI Gateway)" display
    else display;

  toGrokModelToml = {
    slug,
    r,
    context ? null,
    name ? null,
  }: let
    wire = grokWireModel slug r;
    out =
      if r.max_output_tokens != null
      then r.max_output_tokens
      else r.max_input_tokens;
    ctx =
      if context != null
      then context
      else if grokContextPin ? ${slug}
      then grokContextPin.${slug}
      else r.max_input_tokens;
    display =
      if name != null
      then name
      else if grokExtendedName ? ${slug}
      then grokExtendedName.${slug}
      else displayOf r;
    backend = grokApiBackend (r // {id = wire;});
    supportsReasoning = cap r.reasoning;
    efforts =
      if r.reasoning_efforts != null
      then r.reasoning_efforts
      else if supportsReasoning && !isAnthropicId wire
      then ["none" "low" "medium" "high"]
      else null;
    effort =
      if r.reasoning_effort != null
      then r.reasoning_effort
      else if supportsReasoning
      then "high"
      else null;
    lines =
      [
        "[model.${tomlModelKey slug}]"
        "model = ${tomlString wire}"
        "name = ${tomlString display}"
        "model_provider = \"nlk-gateway\""
        "api_backend = ${tomlString backend}"
        "context_window = ${toString ctx}"
        "max_completion_tokens = ${toString out}"
      ]
      ++ lib.optional (isGrokId wire) "system_prompt_label = ${tomlString (grokSystemLabel slug wire display)}"
      ++ lib.optional (isGrokId wire) "supports_backend_search = true"
      ++ lib.optional (efforts != null) "supports_reasoning_effort = true"
      ++ lib.optional (efforts != null) "reasoning_efforts = ${tomlStringArray efforts}"
      ++ lib.optional (effort != null && efforts == null) "reasoning_effort = ${tomlString effort}"
      ++ lib.optional (backend == "messages") ""
      ++ lib.optional (backend == "messages") "[model.${tomlModelKey slug}.extra_headers]"
      ++ lib.optional (backend == "messages") "anthropic-version = \"2023-06-01\"";
  in
    lib.concatStringsSep "\n" lines + "\n";

  grokConfigModelsToml = let
    # One [model.*] per resolved upstream.
    primary =
      map (
        r: let
          slug = grokSlugFor r;
        in {
          inherit slug r;
          context = null;
          name = null;
        }
      )
      resolved;

    # Managed *-extended slugs: extra picker row, same wire id as the base.
    extended =
      lib.filter (e: e != null) (
        map (
          slug: let
            catalogId = grokManagedSlugs.${slug};
            r = resolvedByAlias.${catalogId} or null;
          in
            if !(lib.hasSuffix "-extended" slug) || r == null
            then null
            else {
              inherit slug r;
              context = grokContextPin.${slug} or null;
              name = grokExtendedName.${slug} or null;
            }
        ) (builtins.attrNames grokManagedSlugs)
      );

    # Fold by slug; later entries overwrite (extended after primary).
    bySlug = lib.foldl' (
      acc: e:
        acc // {${e.slug} = e;}
    ) {} (primary ++ extended);

    slugs = lib.sort (a: b: a < b) (builtins.attrNames bySlug);
  in
    lib.concatStrings (
      map (
        slug: let
          e = bySlug.${slug};
        in
          toGrokModelToml {
            inherit slug;
            inherit (e) r;
            context = e.context;
            name = e.name;
          }
      )
      slugs
    );
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
