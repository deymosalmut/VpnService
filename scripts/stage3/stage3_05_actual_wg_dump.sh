#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
export REPORT_DIR

source "scripts/lib/report.sh"

IFACE="${IFACE:-wg1}"
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

main() {
  section "Stage 3.5 actual WG dump"
  log "IFACE=$IFACE"

  if ! command -v wg >/dev/null 2>&1; then
    log "ERROR: wg not found in PATH."
    return 10
  fi

  local actual_file
  actual_file="$REPORT_DIR/stage35_actual_$(date +'%Y-%m-%d_%H-%M-%S').tsv"

  section "Read wg dump"
  if ! wg show "$IFACE" dump | awk -v OFS='\t' '
    NR>1 {
      endpoint=$3
      if (endpoint=="(none)") endpoint=""
      keepalive=$8
      if (keepalive=="0") keepalive=""
      print $1, $4, endpoint, keepalive, 1
    }
  ' > "$actual_file"; then
    log "ERROR: wg show dump failed for iface $IFACE."
    return 11
  fi

  local total
  total="$(awk 'NF>0{c++} END{print c+0}' "$actual_file")"

  summary_kv "ACTUAL_FILE" "$actual_file"
  summary_kv "TOTAL" "$total"

  update_state "STAGE35_ACTUAL_FILE" "$actual_file"
  update_state "STAGE35_ACTUAL_REPORT" "$REPORT_FILE"
  update_state "STAGE35_ACTUAL_TOTAL" "$total"
  update_state "STAGE35_LAST_TS" "$(date +'%Y-%m-%d_%H-%M-%S')"

  return 0
}

report_init "stage35_actual_wg_dump"

rc=0
{
  main
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
