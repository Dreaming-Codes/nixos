#!/usr/bin/env bash
# Snapshot the LiteLLM catalog, then open Grok to reconcile team overrides.
#
# 1. GET /v1/models and /v1/model/info into a temporary directory
# 2. grok with a task prompt to update
#      -> secrets/work/ai-gateway-team-overrides.json
#    using Neuralink sw repo model wiring (Claude / Codex / OpenCode / Grok /
#    LiteLLM) when the gateway omits or mis-reports limits.
#
# Run from anywhere. Does not rebuild the system. cli-proxy-api-nlk-gateway
# reads the overrides from the store after the next home-manager switch.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
base_url="${NLK_AI_GATEWAY_URL:-https://ai-gateway.svc.int.n7k.io}"
out_dir="${repo_root}/secrets/work"
overrides_file="${out_dir}/ai-gateway-team-overrides.json"
catalog_dir="$(mktemp -d)"
models_file="${catalog_dir}/ai-gateway-models.json"
info_file="${catalog_dir}/ai-gateway-model-info.json"
generator="${repo_root}/home/nlk-gateway-cpa-models.ts"

# Neuralink monorepo: model IDs, aliases, and product defaults live here.
sw_repo="${NLK_SW_REPO:-/home/dreamingcodes/Documents/codeProjects/neuralink/sw/root}"
grok_bin="${GROK_BIN:-grok}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing dependency: $1" >&2
    exit 1
  }
}

need curl
need jq
need nlk-llm-proxy
need "$grok_bin"

if [[ ! -d "$out_dir" ]]; then
  echo "error: expected directory missing: $out_dir" >&2
  exit 1
fi

if [[ ! -d "$sw_repo" ]]; then
  echo "error: sw repo not found: $sw_repo" >&2
  echo "  set NLK_SW_REPO to your Neuralink sw checkout" >&2
  exit 1
fi

echo "=== 1/2 Snapshot LiteLLM catalog ==="
token="$(nlk-llm-proxy auth)"
for path in /v1/models /v1/model/info; do
  dest="$models_file"
  [[ "$path" == /v1/model/info ]] && dest="$info_file"
  curl -fsS --max-time 120 -H "Authorization: Bearer ${token}" "${base_url}${path}" | jq -S . >"$dest"
  echo "GET ${path}: $(jq '.data | length' "$dest") models -> ${dest}"
done

# Optional: ensure team managed_config is current (nlkgrok / grok setup).
if command -v nlkgrok >/dev/null 2>&1; then
  echo
  echo "Refreshing Grok team managed_config via nlkgrok setup ..."
  nlkgrok setup >/dev/null 2>&1 || true
elif command -v grok >/dev/null 2>&1; then
  echo
  echo "Refreshing Grok team managed_config via grok setup ..."
  grok setup >/dev/null 2>&1 || true
fi

managed_config="${HOME}/.grok/managed_config.toml"

prompt="$(
  cat <<EOF
# Task: reconcile AI Gateway team overrides

## What just ran

The LiteLLM catalog was just snapshotted (they are scratch files, not part of
the repo):

- \`${models_file}\`  ← GET /v1/models
- \`${info_file}\`     ← GET /v1/model/info

Your job is **not** to re-fetch those. Your job is to inspect them, then
update the hand-maintained overrides file so CLIProxyAPI, and every client
that lists models from it, gets correct names and context windows when
LiteLLM is missing or wrong.

## File you must edit

\`${overrides_file}\`

Schema (keep it valid JSON):

- \`_comment\`: short note about sources
- \`provider_default_context_window\`: fallback when a model is listed in
  \`models\` but has no \`context_window\` (currently 200000)
- \`models\`: map of **gateway model id** → override object

Per-model fields (all optional except that an entry should be useful):

| field | meaning |
| --- | --- |
| \`name\` | human display name for pickers |
| \`api_backend\` | \`messages\` (Anthropic) or \`chat_completions\` |
| \`context_window\` | max input tokens when catalog omits it |
| \`max_output_tokens\` | only if it should differ from context |
| \`vision\` / \`tools\` / \`reasoning\` | booleans |
| \`reasoning_effort\` | e.g. \`"high"\` |
| \`reasoning_efforts\` | array of allowed efforts (GPT Mantle models) |

The generator reads \`name\` and \`context_window\`; the other fields are
reference data.

Keys should be **gateway-facing model ids** as they appear in
\`ai-gateway-models.json\` / \`ai-gateway-model-info.json\`, e.g.
\`global.anthropic.claude-opus-5\`, \`openai.gpt-5.6-sol\`, \`grok-4.5\`.

**Prefer the long / canonical id only.** Do **not** add short aliases
(\`gpt-5.6-sol\`, \`claude-opus-5\`, \`gemini\`, \`grok\`, …) just because
clients or docs mention them. The generator collapses alias ids that share
a LiteLLM upstream onto one picker entry, so one canonical team key usually
covers the whole group (see \`rankId\` in nlk-gateway-cpa-models.ts).

**When an alias key is allowed:** only if that exact id is already present
in the model catalog (\`ai-gateway-models.json\` / model-info) **and** it
needs its own override; e.g. a separate \`litellm_params.model\` upstream
so it does not collapse with the canonical id, or catalog limits/caps for
that id are null/wrong and harnesses would otherwise pick bad values.
Never invent alias keys that are not in the catalog. Drop short-alias
override keys when the canonical entry already covers the group.

## How overrides are consumed

Read \`${generator}\` before editing. Summary:

1. Catalog from models + model-info is preferred when present.
2. Team overrides fill gaps (null / missing context, name, caps, backend).
3. Alias ids that share the same LiteLLM upstream collapse to one picker entry.
4. Models with **no** context from catalog **and** no team override are
   dropped.
5. After you edit overrides, do **not** rebuild Nix unless the user asks;
   just leave the JSON correct for the next home-manager switch.

## Why overrides are needed

LiteLLM often returns null/0/wrong \`max_input_tokens\`, \`max_output_tokens\`,
or capability flags for newer Bedrock / Mantle / xAI routes. Examples that
have historically been empty in model-info: Claude Opus/Sonnet 5, Fable,
GPT-5.6 sol/terra/luna, grok-4.5, gemini flash aliases.

## Where to find authoritative repo overrides (sw monorepo)

Primary checkout: \`${sw_repo}\` (make sure it's on master and synced with upstream if it's not warn the user and refuse to continue)

Search **all** of these. Neuralink wires
models through Claude Code, Codex, OpenCode, Grok, and the LiteLLM
Terraform module:

### 1. Grok team managed config (rich caps + context_window)

- Local sync of team config (after \`nlkgrok setup\` / \`grok setup\`):
  \`${managed_config}\`
- Look at \`[[version_overrides]]\` → \`[version_overrides.model.*]\`:
  \`model\`, \`name\`, \`api_backend\`, \`context_window\`,
  \`reasoning_efforts\`, \`model_provider\`, etc.
- Provider default: \`[model_providers.nlk-gateway] context_window\`
- CI seed / comments:
  \`${sw_repo}/infrastructure/services/gitlab_llm_agent/grok_wrapper.sh\`
- Packaging note (setup applies managed_config):
  \`${sw_repo}/ops/flakes/pkgs/grok-cli/default.nix\`

### 2. Claude Code (default model ids + custom GPT/Grok options)

- \`${sw_repo}/.claude/settings.json\`
  - \`ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS,FABLE}_MODEL\`
  - \`ANTHROPIC_CUSTOM_MODEL_OPTION\` (+ NAME/DESCRIPTION)
  - top-level \`model\`, \`ANTHROPIC_BASE_URL\`
- CI managed settings:
  \`${sw_repo}/infrastructure/services/gitlab_llm_agent/managed-settings.json\`
- Agent model pins / aliases:
  \`${sw_repo}/infrastructure/services/gitlab_llm_agent/common.py\`
  \`${sw_repo}/infrastructure/services/gitlab_llm_agent/README.md\`
  \`${sw_repo}/infrastructure/services/gitlab_llm_agent/src/webhook_handler.py\`

### 3. Codex (ncodex + gateway TOML)

- \`${sw_repo}/ops/flakes/codex-gateway.toml\`
- \`${sw_repo}/ops/flakes/flake.nix\`: \`ncodex\` wrapper (\`model_provider\`,
  base URL, default model, auth via llm_proxy)

### 4. OpenCode

- \`${sw_repo}/opencode.json\`: default/small/agent models (often
  \`amazon-bedrock/…\` ids; map mentally to gateway \`global.anthropic.*\` /
  short names where relevant)
- Flake \`nopencode\` wrapper in \`${sw_repo}/ops/flakes/flake.nix\`

### 5. LiteLLM gateway model list (source of truth for **which ids exist**)

- \`${sw_repo}/infrastructure/terraform/modules/litellm_gateway/main.tf\`
  \`base_models\` / \`model_name\` + \`litellm_params.model\` (Bedrock,
  Mantle, xAI, Vertex). Comments document [1m] aliases, fallbacks, and
  region quirks.
- Related: \`${sw_repo}/infrastructure/terraform/modules/agentic_infra/\`
- Human-oriented model table:
  \`${sw_repo}/ops/llm_proxy/README.md\`

## Procedure

1. Diff / skim the fresh catalog:
   - List model ids in \`${models_file}\` (\`.data[].id\`).
   - In \`${info_file}\`, find entries where \`model_info.max_input_tokens\`
     / \`max_output_tokens\` / capability flags are null, 0, or clearly wrong.
   - Note \`litellm_params.model\` upstream for grouping aliases.
2. Cross-check sw sources above for:
   - New models that need override entries
   - Renamed/removed models to drop from overrides
   - Correct \`context_window\`, display \`name\`, \`api_backend\`, reasoning
3. Prefer **managed_config.toml version_overrides** for Grok/Claude/GPT
   gateway models when present; fall back to product docs / README /
   known Anthropic 1M / Grok 500k / provider defaults.
   Grok \`*-extended\` is a CLI-only 200k/500k pin on the same gateway
   id. Do not add \`*-extended\` keys. Put the larger (extended) window
   on the base catalog id; the generator also folds \`*-extended\` onto
   the base and drops the 200k sibling.
4. Update \`${overrides_file}\` only: keep stable JSON key order where
   practical; preserve \`_comment\` intent; do not rewrite catalog JSON.
5. Sanity-check: every override key must be a real catalog model id.
   Prefer one canonical (long) key per upstream group. Do not keep short
   aliases unless they are in the catalog and need their own override
   (separate upstream or otherwise would leave harnesses with wrong
   limits). Remove stale keys for models no longer in the catalog.
6. Summarize what you changed and which models still lack limits (would
   be skipped by the generator).

## Constraints

- Working directory for edits: \`${repo_root}\` (this nixos dotfiles repo).
- Do **not** run nixos-rebuild / home-manager switch unless asked.
- Do **not** commit unless asked.
- Do not invent context windows; prefer repo/managed_config evidence, then
  well-known product caps, then \`provider_default_context_window\`.
EOF
)"

echo
echo "=== 2/2 Launch Grok to update team overrides ==="
echo "  overrides: ${overrides_file#"$repo_root"/}"
echo "  sw repo:   ${sw_repo}"
echo "  managed:   ${managed_config}"
echo

# Interactive session with the task preloaded. Extra CLI args are forwarded
# (e.g. -m MODEL, --always-approve).
cd "$repo_root"
exec "$grok_bin" --cwd "$repo_root" "$@" "$prompt"
