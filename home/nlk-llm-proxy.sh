# Neuralink AI gateway helper (body for pkgs.writeShellApplication).
#
#   nlk-llm-proxy login   — interactive SSO (device code)
#   nlk-llm-proxy auth    — print a fresh id_token (apiKeyHelper); also installs
#                           it into the user environment for Zed/OpenCode/etc.
#   nlk-llm-proxy env     — auth + print shell exports (eval/source me)
#
# On every successful auth/login the token is written to:
#   - ~/.config/environment.d/80-nlk-gateway.conf  (next graphical login)
#   - systemd --user environment                   (new user services)
#   - ~/.local/share/opencode/auth.json            (OpenCode nlk-gateway key)
set -euo pipefail

llm_proxy_py="@llm_proxy_py@"

die() {
  echo "nlk-llm-proxy: $*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

need python3

run_proxy() {
  python3 "$llm_proxy_py" "$@"
}

# Install token where stock tools look (no per-app wrappers).
install_user_env() {
  local key="$1"
  local env_dir="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d"
  local env_file="$env_dir/80-nlk-gateway.conf"
  local auth_dir="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
  local auth_file="$auth_dir/auth.json"

  mkdir -p "$env_dir"
  # environment.d is loaded at login by pam/systemd — keeps desktop apps fed
  # after the next session start without wrapping zeditor.
  umask 077
  cat >"$env_file" <<EOF
NLK_GATEWAY_API_KEY=${key}
OPENAI_API_KEY=${key}
ANTHROPIC_API_KEY=${key}
EOF

  # Live user-manager env (helps systemd --user units; some DEs pick this up).
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user set-environment \
      "NLK_GATEWAY_API_KEY=${key}" \
      "OPENAI_API_KEY=${key}" \
      "ANTHROPIC_API_KEY=${key}" 2>/dev/null || true
  fi

  # OpenCode stores provider keys in auth.json (not env).
  if command -v jq >/dev/null 2>&1; then
    mkdir -p "$auth_dir"
    if [[ -f "$auth_file" ]]; then
      jq --arg k "$key" '.["nlk-gateway"] = {"type":"api","key":$k}' \
        "$auth_file" >"$auth_file.tmp"
    else
      jq -n --arg k "$key" '{"nlk-gateway":{"type":"api","key":$k}}' \
        >"$auth_file.tmp"
    fi
    mv "$auth_file.tmp" "$auth_file"
    chmod 600 "$auth_file"
  fi
}

# Fresh token + install; prints token on stdout (apiKeyHelper contract).
do_auth() {
  local key
  key="$(run_proxy auth)"
  [[ -n "$key" ]] || die "empty token (try: nlk-llm-proxy login)"
  install_user_env "$key"
  printf '%s\n' "$key"
}

do_login() {
  run_proxy login "$@"
  # After interactive login, mint/install a token for the session.
  do_auth >/dev/null
  echo "nlk-llm-proxy: gateway token installed into user environment." >&2
}

do_env() {
  local key
  key="$(do_auth)"
  # Shell-agnostic exports for: eval "$(nlk-llm-proxy env)"
  printf "export NLK_GATEWAY_API_KEY=%q\n" "$key"
  printf "export OPENAI_API_KEY=%q\n" "$key"
  printf "export ANTHROPIC_API_KEY=%q\n" "$key"
}

usage() {
  cat <<'EOF'
Usage: nlk-llm-proxy <command>

  login   One-time SSO (device code), then install token into user env
  auth    Print fresh id_token; install into user env (Grok/Claude apiKeyHelper)
  env     Like auth, but print export lines for eval/source in a shell

EOF
}

cmd="${1:-}"
case "$cmd" in
auth)
  shift
  do_auth "$@"
  ;;
login)
  shift
  do_login "$@"
  ;;
env)
  shift
  do_env "$@"
  ;;
-h | --help | help | "")
  usage
  [[ -n "$cmd" ]] || exit 1
  ;;
*)
  # Pass through unknown subcommands to the python tool if it grows more later.
  run_proxy "$@"
  ;;
esac
