#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$OUT_DIR"

source "$REPO_ROOT/scripts/lib/report.sh"

ts(){ date +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$OUT_DIR/report_stage35_diff_$(ts).log"

LAST_ENV="$OUT_DIR/stage35_last_run.env"
DESIRED_FILE="${DESIRED_FILE:-}"
ACTUAL_FILE="${ACTUAL_FILE:-}"

NOW_TS="$(ts)"
PLAN_FILE="$OUT_DIR/stage35_plan_${NOW_TS}.tsv"
DIFF_FILE="$OUT_DIR/stage35_diff_${NOW_TS}.txt"

report_init "stage35_diff"
rc=0
{
  section "Stage 3.5 — DIFF/PLAN (read-only)"
  if [[ -f "$LAST_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$LAST_ENV"
  fi

  DESIRED_FILE="${DESIRED_FILE:-}"
  ACTUAL_FILE="${ACTUAL_FILE:-}"

  log "DESIRED_FILE=$DESIRED_FILE"
  log "ACTUAL_FILE=$ACTUAL_FILE"
  [[ -n "${DESIRED_FILE:-}" && -f "$DESIRED_FILE" ]] || { log "FAIL missing desired file"; exit 10; }
  [[ -n "${ACTUAL_FILE:-}" && -f "$ACTUAL_FILE" ]] || { log "FAIL missing actual file"; exit 11; }

  d_pub="/tmp/stage35_desired_pub_$$.txt"
  a_pub="/tmp/stage35_actual_pub_$$.txt"
  plan="/tmp/stage35_plan_$$.tsv"

  section "Normalize desired/actual -> pubkey sets"
  run_step_tee "Desired pubkeys (sorted)" bash -lc "
    set -Eeuo pipefail
    awk -F \$'\\t' 'NF>=1 && length(\$1)>0 {print \$1}' '$DESIRED_FILE' \
      | sed 's/\\r$//' | sed '/^\\s*$/d' \
      | LC_ALL=C sort -u > '$d_pub'
    wc -l '$d_pub'
    head -n 20 '$d_pub'
  "
  run_step_tee "Actual pubkeys (sorted)" bash -lc "
    set -Eeuo pipefail
    awk -F \$'\\t' 'NF>=1 && length(\$1)>0 {print \$1}' '$ACTUAL_FILE' \
      | sed 's/\\r$//' | sed '/^\\s*$/d' \
      | LC_ALL=C sort -u > '$a_pub'
    wc -l '$a_pub'
    head -n 20 '$a_pub'
  "

  section "Compute plan (ADD/DEL by pubkey) [robust]"
  : >"$plan"

  # ADD: desired - actual
  if [[ -s "$a_pub" ]]; then
    grep -Fvx -f "$a_pub" "$d_pub" | awk -v OFS=$'\t' '{print "ADD",$1}' >>"$plan" || true
  else
    awk -v OFS=$'\t' 'NF{print "ADD",$1}' "$d_pub" >>"$plan" || true
  fi

  # DEL: actual - desired
  if [[ -s "$d_pub" ]]; then
    grep -Fvx -f "$d_pub" "$a_pub" | awk -v OFS=$'\t' '{print "DEL",$1}' >>"$plan" || true
  else
    awk -v OFS=$'\t' 'NF{print "DEL",$1}' "$a_pub" >>"$plan" || true
  fi

  add_cnt="$(grep -c $'^ADD\t' "$plan" 2>/dev/null || true)"
  del_cnt="$(grep -c $'^DEL\t' "$plan" 2>/dev/null || true)"

  if [[ -s "$plan" ]]; then
    RESULT="CHANGES_PENDING"
  else
    RESULT="NO_CHANGES"
  fi

  section "Write artifacts"
  cp -a "$plan" "$PLAN_FILE"

  {
    echo "RESULT=$RESULT"
    echo "ADD=$add_cnt"
    echo "DEL=$del_cnt"
    echo "DESIRED_FILE=$DESIRED_FILE"
    echo "ACTUAL_FILE=$ACTUAL_FILE"
    echo "PLAN_FILE=$PLAN_FILE"
    echo
    echo "Plan preview (top 50):"
    head -n 50 "$PLAN_FILE" || true
  } > "$DIFF_FILE"

  section "Summary"
  log "RESULT=$RESULT"
  log "ADD=$add_cnt DEL=$del_cnt"
  log "PLAN_FILE=$PLAN_FILE"
  log "DIFF_FILE=$DIFF_FILE"

  {
    echo "UPDATED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "IFACE=${IFACE:-wg1}"
    echo "DESIRED_FILE=$DESIRED_FILE"
    echo "ACTUAL_FILE=$ACTUAL_FILE"
    echo "PLAN_FILE=$PLAN_FILE"
    echo "DIFF_FILE=$DIFF_FILE"
  } > "$LAST_ENV"

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
