#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
LAST_ENV="${LAST_ENV:-$OUT_DIR/stage35_last_run.env}"

mkdir -p "$OUT_DIR"
ts(){ date -u +"%Y-%m-%d_%H-%M-%S"; }
now_iso(){ date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log(){ echo -e "$*"; }
die(){ log "FAIL: $*"; exit 1; }

# Load last run (required)
[[ -f "$LAST_ENV" ]] || die "missing $LAST_ENV (run stage3_05_menu.sh steps 1->3 first)"
# shellcheck disable=SC1090
source "$LAST_ENV"

: "${IFACE:?missing IFACE in $LAST_ENV}"
: "${DESIRED_FILE:?missing DESIRED_FILE in $LAST_ENV}"
: "${ACTUAL_FILE:?missing ACTUAL_FILE in $LAST_ENV}"
: "${PLAN_FILE:?missing PLAN_FILE in $LAST_ENV}"
: "${DIFF_FILE:?missing DIFF_FILE in $LAST_ENV}"

REPORT="$OUT_DIR/report_stage35_finalize_$(ts).log"
: >"$REPORT"

# Helpers for counts
count_lines(){ [[ -f "$1" ]] && wc -l <"$1" | tr -d ' ' || echo 0; }

DESIRED_N="$(count_lines "$DESIRED_FILE")"
ACTUAL_N="$(count_lines "$ACTUAL_FILE")"
PLAN_N="$(count_lines "$PLAN_FILE")"

{
  echo ">>> Stage 3.5 FINALIZE"
  echo "TIME_UTC: $(now_iso)"
  echo "IFACE: $IFACE"
  echo
  echo "DESIRED_FILE=$DESIRED_FILE (lines=$DESIRED_N)"
  echo "ACTUAL_FILE=$ACTUAL_FILE (lines=$ACTUAL_N)"
  echo "PLAN_FILE=$PLAN_FILE (lines=$PLAN_N)"
  echo "DIFF_FILE=$DIFF_FILE"
  echo
  echo ">>> wg show (sanity)"
  wg show "$IFACE" || true
  echo
  echo ">>> Diff excerpt"
  head -n 80 "$DIFF_FILE" 2>/dev/null || true
} | tee -a "$REPORT"

# Update last env with LAST_REPORT + UPDATED_UTC (idempotent)
tmp="$(mktemp)"
grep -vE '^(LAST_REPORT|UPDATED_UTC)=' "$LAST_ENV" >"$tmp" || true
{
  echo "UPDATED_UTC=$(now_iso)"
  echo "LAST_REPORT=$REPORT"
  cat "$tmp"
} >"$LAST_ENV"
rm -f "$tmp"

log
log "OK finalized."
log "LAST_ENV=$LAST_ENV"
log "LAST_REPORT=$REPORT"

# Quick green/red decision
if [[ "$PLAN_N" -eq 0 && "$DESIRED_N" -eq "$ACTUAL_N" ]]; then
  log "RESULT=GREEN (no pending changes)"
  exit 0
fi

log "RESULT=YELLOW (review counts: desired=$DESIRED_N actual=$ACTUAL_N plan=$PLAN_N)"
exit 0
