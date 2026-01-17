#!/usr/bin/env bash
# PURPOSE: Verify login rate limiting works by sending bad login attempts until 429
# EXPECTED OUTPUT: At least one HTTP 429 response after 10+ bad login attempts
# EXIT CODE: 0 on success (rate limit triggered), 1 on failure

set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "LOGIN RATE LIMIT SMOKE TEST"

need_cmd curl

attempts=12
count_401=0
count_429=0

log "Sending $attempts bad login attempts to trigger rate limiting..."

for i in $(seq 1 "$attempts"); do
  status="$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$API_BASE_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"wrong-password\"}" 2>/dev/null || echo "000")"

  if [[ "$status" == "401" ]]; then
    count_401=$((count_401 + 1))
    log "[$i/$attempts] 401 Unauthorized"
  elif [[ "$status" == "429" ]]; then
    count_429=$((count_429 + 1))
    log "[$i/$attempts] 429 Too Many Requests ✓"
  else
    warn "[$i/$attempts] Unexpected status: $status"
  fi
done

log "Results: 401=$count_401, 429=$count_429"

if [[ "$count_429" -ge 1 ]]; then
  hr; log "✓ PASS: Rate limiting triggered"
  exit 0
fi

err "FAIL: Expected at least one 429, got none"
exit 1
