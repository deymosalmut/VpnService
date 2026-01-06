#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
API_URL="${API_URL:-http://localhost:5272}"
IFACE="${IFACE:-wg1}"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$REPORT_DIR/report_stage35_apply_$(ts).log"
: >"$REPORT_FILE"

log(){ echo -e "$*" | tee -a "$REPORT_FILE"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

LAST_ENV="$REPORT_DIR/stage35_last_run.env"
TOKEN_FILE="$REPORT_DIR/last_token.txt"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"

# Load last-run env (safe parse: only KEY=VALUE with no spaces expected)
if [[ -f "$LAST_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$LAST_ENV" || true
fi

PLAN_FILE="${PLAN_FILE:-}"
if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
  log "FAIL missing PLAN_FILE in $LAST_ENV (or file not found)"
  exit 20
fi

add_count="$(awk -F'\t' '$1=="ADD"{c++} END{print c+0}' "$PLAN_FILE" 2>/dev/null || echo 0)"
del_count="$(awk -F'\t' '$1=="DEL"{c++} END{print c+0}' "$PLAN_FILE" 2>/dev/null || echo 0)"

write_last_env() {
  # Keep existing artifacts if set, but never write values with spaces.
  local now; now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  {
    echo "UPDATED_UTC=$now"
    echo "IFACE=$IFACE"
    [[ -n "${DESIRED_FILE:-}" ]] && echo "DESIRED_FILE=$DESIRED_FILE"
    [[ -n "${ACTUAL_FILE:-}" ]] && echo "ACTUAL_FILE=$ACTUAL_FILE"
    [[ -n "${DIFF_FILE:-}" ]] && echo "DIFF_FILE=$DIFF_FILE"
    echo "PLAN_FILE=$PLAN_FILE"
    echo "LAST_REPORT=$REPORT_FILE"
    echo "ADD=$add_count"
    echo "DEL=$del_count"
  } >"$LAST_ENV"
}

auth_header() {
  if [[ -s "$TOKEN_FILE" ]]; then
    local tok; tok="$(cat "$TOKEN_FILE" | tr -d '\r\n')"
    echo "Authorization: Bearer $tok"
  fi
}

login() {
  section "AUTH: login (refresh token)"
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
import json
p="$out"
j=json.load(open(p,"r",encoding="utf-8"))
tok=j.get("token") or j.get("accessToken") or j.get("access_token")
if not tok:
  raise SystemExit("FAIL cannot find token field in login response")
open("$TOKEN_FILE","w",encoding="utf-8").write(tok.strip()+"\n")
print("OK token saved:", "$TOKEN_FILE")
PY
}

probe_state() {
  local out="$REPORT_DIR/stage35_state_probe_$(ts).json"
  local code
  local ah; ah="$(auth_header || true)"
  if [[ -n "$ah" ]]; then
    code="$(curl -sS -o "$out" -w "%{http_code}" -H "$ah" "$API_URL/api/v1/admin/wg/state" 2>>"$REPORT_FILE" || true)"
  else
    code="$(curl -sS -o "$out" -w "%{http_code}" "$API_URL/api/v1/admin/wg/state" 2>>"$REPORT_FILE" || true)"
  fi
  echo "$code"
}

call_reconcile() {
  local method="$1"
  local out="$REPORT_DIR/stage35_reconcile_apply_$(ts).json"
  local ah; ah="$(auth_header || true)"
  local code

  if [[ -n "$ah" ]]; then
    code="$(curl -sS -o "$out" -w "%{http_code}" -X "$method" \
      -H "$ah" -H "Content-Type: application/json" \
      "$API_URL/api/v1/admin/wg/reconcile" 2>>"$REPORT_FILE" || true)"
  else
    code="$(curl -sS -o "$out" -w "%{http_code}" -X "$method" \
      -H "Content-Type: application/json" \
      "$API_URL/api/v1/admin/wg/reconcile" 2>>"$REPORT_FILE" || true)"
  fi

  log "HTTP=$code METHOD=$method OUT=$out"
  if [[ "$code" == "200" ]]; then
    log "OK reconcile apply success."
    return 0
  fi

  # If 405, dump Allow header
  if [[ "$code" == "405" ]]; then
    local allow
    allow="$(curl -sS -D - -o /dev/null -X "$method" "$API_URL/api/v1/admin/wg/reconcile" 2>>"$REPORT_FILE" \
      | awk 'BEGIN{IGNORECASE=1} /^Allow:/{sub(/\r$/,""); print $0}')"
    log "ALLOW=${allow:-<none>}"
  fi

  return 1
}

main() {
  section "Stage 3.5 — RECONCILE APPLY (controlled)"
  log "API_URL=$API_URL"
  log "IFACE=$IFACE"
  log "LAST_ENV=$LAST_ENV"
  log "TOKEN_FILE=$TOKEN_FILE"
  hr
  log "PLAN_FILE=$PLAN_FILE"
  log "ADD=$add_count DEL=$del_count"
  hr

  section "Plan preview (top 50)"
  head -n 50 "$PLAN_FILE" | tee -a "$REPORT_FILE" || true

  section "SAFETY GATE"
  log "This will call: * /api/v1/admin/wg/reconcile (method auto-detected)"
  log "Type APPLY to continue."
  read -r -p "> " gate
  gate="$(printf '%s' "$gate" | tr -d '\r' | xargs || true)"
  if [[ "$gate" != "APPLY" ]]; then
    log "Abort: gate not passed."
    write_last_env
    exit 30
  fi

  section "Auth precheck (state probe; auto-login on 401)"
  local st
  st="$(probe_state)"
  log "STATE_PROBE_HTTP=$st"
  if [[ "$st" == "401" || "$st" == "000" ]]; then
    login
    st="$(probe_state)"
    log "STATE_PROBE_HTTP_AFTER_LOGIN=$st"
    if [[ "$st" == "401" || "$st" == "000" ]]; then
      log "FAIL cannot authorize even after login."
      write_last_env
      exit 41
    fi
  fi

  section "Reconcile APPLY (auto-detect method)"
  # Try methods in priority order; 405 will be handled/logged
  if call_reconcile GET; then :;
  elif call_reconcile POST; then :;
  elif call_reconcile PUT; then :;
  elif call_reconcile PATCH; then :;
  else
    log "FAIL reconcile apply: all methods failed. Run api doctor for details:"
    log "  bash $REPO_ROOT/scripts/stage3/stage3_05_api_doctor.sh"
    write_last_env
    exit 50
  fi

  section "Post-check: WG state (read-only)"
  local out="$REPORT_DIR/stage35_wg_state_$(ts).json"
  local ah; ah="$(auth_header || true)"
  if [[ -n "$ah" ]]; then
    curl -fsS "$API_URL/api/v1/admin/wg/state" -H "$ah" -o "$out" 2>>"$REPORT_FILE" || true
  else
    curl -fsS "$API_URL/api/v1/admin/wg/state" -o "$out" 2>>"$REPORT_FILE" || true
  fi
  log "WG_STATE_JSON=$out"
  head -c 800 "$out" 2>/dev/null | tee -a "$REPORT_FILE" || true
  echo | tee -a "$REPORT_FILE"

  section "DONE"
  write_last_env
  log "Report saved: $REPORT_FILE"
}

main "$@"
