#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
API_URL="${API_URL:-http://localhost:5272}"
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$REPORT_DIR/report_stage35_api_doctor_$(ts).log"
: >"$REPORT_FILE"

log(){ echo -e "$*" | tee -a "$REPORT_FILE"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

TOKEN_FILE="$REPORT_DIR/last_token.txt"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"

curl_code() { # method url [auth=0/1] [out]
  local method="$1" url="$2" auth="${3:-0}" out="${4:-/dev/null}"
  local hdr=()
  if [[ "$auth" == "1" && -s "$TOKEN_FILE" ]]; then
    local tok; tok="$(cat "$TOKEN_FILE" | tr -d '\r\n')"
    hdr+=(-H "Authorization: Bearer $tok")
  fi
  curl -sS -o "$out" -w "%{http_code}" -X "$method" "${hdr[@]}" "$url" 2>>"$REPORT_FILE" || echo "000"
}

curl_allow() { # method url
  local method="$1" url="$2"
  curl -sS -D - -o /dev/null -X "$method" "$url" 2>>"$REPORT_FILE" | awk 'BEGIN{IGNORECASE=1} /^Allow:/{sub(/\r$/,""); print $0}'
}

login() {
  section "AUTH: login (writes token to reports/last_token.txt)"
  local out="$REPORT_DIR/stage35_login_$(ts).json"
  local code
  code="$(curl -sS -o "$out" -w "%{http_code}" \
    -X POST "$API_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASSWORD\"}" \
    2>>"$REPORT_FILE" || true)"
  log "HTTP=$code BODY=$out"
  if [[ "$code" != "200" ]]; then
    log "FAIL login http=$code"
    return 1
  fi
  python3 - <<PY >>"$REPORT_FILE" 2>&1
import json,sys
p="$out"
j=json.load(open(p,"r",encoding="utf-8"))
tok=j.get("token") or j.get("accessToken") or j.get("access_token")
if not tok:
  raise SystemExit("FAIL cannot find token field in login response")
open("$TOKEN_FILE","w",encoding="utf-8").write(tok.strip()+"\n")
print("OK token saved:", "$TOKEN_FILE")
PY
}

main() {
  section "Stage 3.5 — API DOCTOR"
  log "API_URL=$API_URL"
  log "TOKEN_FILE=$TOKEN_FILE (exists=$(test -s "$TOKEN_FILE" && echo yes || echo no))"
  log ""

  section "Probe /health (no auth)"
  local c; c="$(curl_code GET "$API_URL/health" 0 "$REPORT_DIR/stage35_health_$(ts).txt")"
  log "GET /health => $c"

  section "Probe /api/v1/admin/wg/state (no auth)"
  c="$(curl_code GET "$API_URL/api/v1/admin/wg/state" 0 "$REPORT_DIR/stage35_state_noauth_$(ts).json")"
  log "GET /api/v1/admin/wg/state => $c"

  section "Probe /api/v1/admin/wg/state (with token if present)"
  c="$(curl_code GET "$API_URL/api/v1/admin/wg/state" 1 "$REPORT_DIR/stage35_state_auth_$(ts).json")"
  log "GET /api/v1/admin/wg/state (auth) => $c"

  if [[ "$c" == "401" || "$c" == "000" ]]; then
    login || true
    c="$(curl_code GET "$API_URL/api/v1/admin/wg/state" 1 "$REPORT_DIR/stage35_state_auth2_$(ts).json")"
    log "GET /api/v1/admin/wg/state (auth after login) => $c"
  fi

  section "Probe reconcile endpoint methods (no body)"
  for m in GET POST PUT PATCH; do
    local url="$API_URL/api/v1/admin/wg/reconcile"
    local out="$REPORT_DIR/stage35_reconcile_${m}_$(ts).out"
    c="$(curl_code "$m" "$url" 1 "$out")"
    log "$m /api/v1/admin/wg/reconcile => $c out=$out"
    if [[ "$c" == "405" ]]; then
      log "  $(curl_allow "$m" "$url")"
    fi
  done

  section "DONE"
  log "Report: $REPORT_FILE"
}

main "$@"
