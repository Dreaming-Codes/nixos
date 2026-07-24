#!/usr/bin/env bash
# Refresh secrets/work/ai-gateway-*.json from the corp LiteLLM gateway.
# Run from anywhere; resolves the nixos repo via this script's location.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${repo_root}/secrets/work"
base_url="${NLK_AI_GATEWAY_URL:-https://ai-gateway.svc.int.n7k.io}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing dependency: $1" >&2
    exit 1
  }
}

need curl
need jq

if [[ ! -d "$out_dir" ]]; then
  echo "error: expected directory missing: $out_dir" >&2
  exit 1
fi

# Prefer installed wrapper; fall back to the git-crypt'd script in-tree.
if command -v nlk-llm-proxy >/dev/null 2>&1; then
  auth_cmd=(nlk-llm-proxy auth)
elif [[ -f "$out_dir/llm_proxy.py" ]]; then
  need python3
  auth_cmd=(python3 "$out_dir/llm_proxy.py" auth)
else
  echo "error: nlk-llm-proxy not on PATH and $out_dir/llm_proxy.py missing" >&2
  exit 1
fi

echo "Authenticating via ${auth_cmd[*]} ..."
token="$("${auth_cmd[@]}")"
if [[ -z "$token" ]]; then
  echo "error: empty token from auth (try: nlk-llm-proxy login)" >&2
  exit 1
fi

fetch() {
  local path="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  echo "GET ${base_url}${path} → ${dest#"$repo_root"/}"
  if ! curl -fsS --max-time 120 \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json" \
    "${base_url}${path}" \
    | jq -S . >"$tmp"; then
    echo "error: failed to fetch or parse ${path}" >&2
    exit 1
  fi

  local count
  count="$(jq '.data | length' "$tmp")"
  if [[ "$count" -lt 1 ]]; then
    echo "error: ${path} returned no models (.data empty)" >&2
    exit 1
  fi

  mv "$tmp" "$dest"
  trap - RETURN
  echo "  wrote ${count} models ($(wc -c <"$dest" | tr -d ' ') bytes)"
}

fetch /v1/models "${out_dir}/ai-gateway-models.json"
fetch /v1/model/info "${out_dir}/ai-gateway-model-info.json"

echo
echo "Done. Review with:"
echo "  git -C ${repo_root} status -- secrets/work/"
echo "OpenCode/Zed lists rebuild from home/nlk-gateway-models.nix on next HM switch."
