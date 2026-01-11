#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "ADMIN WG STATE"

need_cmd curl

token="$(load_token)"
if [[ -z "$token" ]]; then
  err "TOKEN not found. Run [7] Auth first."
  exit 1
fi

url="$API_BASE_URL/api/v1/admin/wg/state?iface=$WG_IFACE"
log "GET $url"
curl -i -sS "$url" -H "Authorization: Bearer $token"
echo
hr; log "OK"
