# Neuralink AI gateway helper (body for pkgs.writeShellApplication).
#
#   nlk-llm-proxy login   - interactive SSO (device code)
#   nlk-llm-proxy auth    - print a fresh id_token (apiKeyHelper contract)
#   nlk-llm-proxy logout  - drop cached identity-proxy credential
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

do_auth() {
  local key
  key="$(run_proxy auth)"
  [[ -n "$key" ]] || die "empty token (try: nlk-llm-proxy login)"
  printf '%s\n' "$key"
}

do_login() {
  run_proxy login "$@"
  do_auth >/dev/null
}

do_logout() {
  run_proxy logout "$@"
}

usage() {
  cat <<'EOF'
Usage: nlk-llm-proxy <command>

  login    One-time SSO (device code)
  auth     Print a fresh id_token (apiKeyHelper)
  logout   Remove the cached credential

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
logout)
  shift
  do_logout "$@"
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
