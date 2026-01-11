#!/usr/bin/env bash
set -euo pipefail

log()  { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err()  { echo -e "[ERR ] $*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; return 1; }
}

hr() { echo "----------------------------------------"; }

# Defaults (можно переопределять через ENV)
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:5272}"
WG_IFACE="${WG_IFACE:-wg1}"

# Admin login defaults (под твою реализацию)
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin123}"

# Token file to persist between steps
TOKEN_FILE="${TOKEN_FILE:-/tmp/vpnservice_token.txt}"

save_token() {
  local token="$1"
  echo -n "$token" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE" || true
}

load_token() {
  if [[ -f "$TOKEN_FILE" ]]; then
    cat "$TOKEN_FILE"
  else
    echo ""
  fi
}
