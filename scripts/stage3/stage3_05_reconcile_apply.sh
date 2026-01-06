#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
<<<<<<< HEAD
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
export REPORT_DIR

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

IFACE="${IFACE:-wg1}"
APP_DB_ENV="$REPO_ROOT/infra/local/app-db.env"
STATE_FILE="$REPORT_DIR/stage35_last_run.env"

update_state() {
  local key="$1"
  local value="$2"
  local tmp="${STATE_FILE}.tmp"
  if [[ -f "$STATE_FILE" ]]; then
    awk -v k="$key" -F= '$1!=k {print}' "$STATE_FILE" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s=%q\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi
}

main() {
  section "Stage 3.5 reconcile apply"

  section "Load app DB env"
  if ! load_app_db_env "$APP_DB_ENV"; then
    log "ERROR: failed to load app DB env."
    return 12
  fi
  log "Target IFACE: $IFACE"
  log "DB: $PG_HOST:$PG_PORT/$PG_DATABASE user=$PG_USER"

  local plan_file="${1:-}"
  if [[ -z "$plan_file" ]]; then
    load_state
    plan_file="${STAGE35_PLAN_FILE:-}"
  fi

  if [[ -z "$plan_file" ]]; then
    log "ERROR: plan file not provided and not found in state."
    return 10
  fi
  if [[ ! -f "$plan_file" ]]; then
    log "ERROR: plan file not found: $plan_file"
    return 11
  fi

  local add rem upd dis total
  add="$(awk -F'\t' '$1=="ADD"{c++} END{print c+0}' "$plan_file")"
  rem="$(awk -F'\t' '$1=="REMOVE"{c++} END{print c+0}' "$plan_file")"
  upd="$(awk -F'\t' '$1=="UPDATE"{c++} END{print c+0}' "$plan_file")"
  dis="$(awk -F'\t' '$1=="DISABLE"{c++} END{print c+0}' "$plan_file")"
  total=$((add + rem + upd + dis))

  summary_kv "PLAN_FILE" "$plan_file"
  summary_kv "ADD" "$add"
  summary_kv "REMOVE" "$rem"
  summary_kv "UPDATE" "$upd"
  summary_kv "DISABLE" "$dis"
  summary_kv "TOTAL_CHANGES" "$total"

  section "SAFETY GATE"
  log "Type APPLY to continue."
  read -r -p "> " gate
  if [[ "$gate" != "APPLY" ]]; then
    log "Abort: gate not passed."
    return 30
  fi

  section "Apply plan to WG runtime"
  while IFS=$'\t' read -r action pub allowed endpoint keepalive enabled; do
    if [[ -z "${action:-}" || -z "${pub:-}" ]]; then
      continue
    fi
    case "$action" in
      ADD|UPDATE)
        if [[ -z "${allowed:-}" ]]; then
          log "ERROR: allowed_ips empty for $pub"
          return 40
        fi
        cmd=(wg set "$IFACE" peer "$pub" allowed-ips "$allowed")
        if [[ -n "${endpoint:-}" ]]; then
          cmd+=(endpoint "$endpoint")
        fi
        if [[ -n "${keepalive:-}" ]]; then
          cmd+=(persistent-keepalive "$keepalive")
        fi
        if ! run_step "WG $action $pub" "${cmd[@]}"; then
          return 42
        fi
        ;;
      REMOVE|DISABLE)
        if ! run_step "WG $action $pub" wg set "$IFACE" peer "$pub" remove; then
          return 43
        fi
        ;;
      *)
        log "ERROR: unknown action '$action' for $pub"
        return 41
        ;;
    esac
  done < "$plan_file"

  section "Post-apply verification"
  load_state
  local desired_file="${STAGE35_DESIRED_FILE:-}"
  if [[ -z "$desired_file" || ! -f "$desired_file" ]]; then
    log "Desired file missing in state; regenerating desired dump."
    if ! bash "scripts/stage3/stage3_05_desired_db_dump.sh"; then
      log "ERROR: desired dump failed."
      return 50
    fi
    load_state
    desired_file="${STAGE35_DESIRED_FILE:-}"
  fi
  if [[ -z "$desired_file" || ! -f "$desired_file" ]]; then
    log "ERROR: desired file not found for verification."
    return 51
  fi

  if ! bash "scripts/stage3/stage3_05_actual_wg_dump.sh"; then
    log "ERROR: actual WG dump failed after apply."
    return 52
  fi
  load_state
  local actual_file="${STAGE35_ACTUAL_FILE:-}"
  if [[ -z "$actual_file" || ! -f "$actual_file" ]]; then
    log "ERROR: actual file not found for verification."
    return 53
  fi

  if ! bash "scripts/stage3/stage3_05_diff.sh" "$desired_file" "$actual_file"; then
    local diff_rc=$?
    log "ERROR: post-apply diff not clean (rc=$diff_rc)."
    return 54
  fi

  summary_kv "POST_APPLY_DIFF" "NO_CHANGES"
  update_state "STAGE35_APPLY_REPORT" "$REPORT_FILE"
  update_state "STAGE35_LAST_TS" "$(date +'%Y-%m-%d_%H-%M-%S')"

  return 0
}

report_init "stage35_reconcile_apply"
update_state "STAGE35_APPLY_REPORT" "$REPORT_FILE"

rc=0
{
  main "$@"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
=======
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
>>>>>>> 68d3b6b (fix)
