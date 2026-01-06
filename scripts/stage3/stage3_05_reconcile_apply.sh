#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
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
