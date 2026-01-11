#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "LOGIN RATE LIMIT SMOKE TEST"

need_cmd curl

attempts=11
count_401=0
count_429=0

for i in $(seq 1 "$attempts"); do
  status="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$API_BASE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"wrong-password\"}")"

  if [[ "$status" == "401" ]]; then
    count_401=$((count_401 + 1))
  elif [[ "$status" == "429" ]]; then
    count_429=$((count_429 + 1))
  else
    warn "Unexpected status: $status"
  fi
done

log "401 count: $count_401"
log "429 count: $count_429"

if [[ "$count_429" -ge 1 ]]; then
  hr; log "OK"
  exit 0
fi

err "Expected at least one 429"
exit 1
