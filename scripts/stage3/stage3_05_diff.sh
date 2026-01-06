#!/usr/bin/env bash
set -Eeuo pipefail
<<<<<<< HEAD

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
export REPORT_DIR

source "scripts/lib/report.sh"

STATE_FILE="$REPORT_DIR/stage35_last_run.env"
PLAN_FILE=""

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

write_section() {
  local diff_file="$1"
  local title="$2"
  local action="$3"
  {
    echo "$title"
    awk -F'\t' -v act="$action" 'BEGIN{found=0} $1==act{print; found=1} END{if(!found) print "(none)"}' "$PLAN_FILE"
    echo
  } >> "$diff_file"
}

main() {
  section "Stage 3.5 diff/plan"

  local desired_file="${1:-}"
  local actual_file="${2:-}"

  if [[ -z "$desired_file" && -z "$actual_file" ]]; then
    log "No input files provided; generating desired + actual dumps."
    if ! bash "scripts/stage3/stage3_05_desired_db_dump.sh"; then
      log "ERROR: desired dump failed."
      return 13
    fi
    if ! bash "scripts/stage3/stage3_05_actual_wg_dump.sh"; then
      log "ERROR: actual dump failed."
      return 14
    fi
    load_state
    desired_file="${STAGE35_DESIRED_FILE:-}"
    actual_file="${STAGE35_ACTUAL_FILE:-}"
  elif [[ -z "$desired_file" || -z "$actual_file" ]]; then
    log "ERROR: both desired and actual file paths must be provided."
    return 10
  fi

  if [[ -z "$desired_file" || ! -f "$desired_file" ]]; then
    log "ERROR: desired file not found: $desired_file"
    return 11
  fi
  if [[ -z "$actual_file" || ! -f "$actual_file" ]]; then
    log "ERROR: actual file not found: $actual_file"
    return 12
  fi

  local diff_file plan_file plan_tmp counts_line
  diff_file="$REPORT_DIR/stage35_diff_$(date +'%Y-%m-%d_%H-%M-%S').txt"
  plan_file="$REPORT_DIR/stage35_plan_$(date +'%Y-%m-%d_%H-%M-%S').tsv"
  plan_tmp="${plan_file}.tmp"

  : > "$plan_tmp"

  if ! counts_line="$(awk -F'\t' -v OFS='\t' -v plan="$plan_tmp" '
    function norm_keepalive(v){ if (v=="" || v=="0") return ""; return v }
    function norm_endpoint(v){ if (v=="(none)") return ""; return v }
    function norm_enabled(v){ return (v=="0") ? "0" : "1" }
    FNR==NR {
      key=$1
      if (key=="") next
      d_allowed[key]=$2
      d_endpoint[key]=norm_endpoint($3)
      d_keep[key]=norm_keepalive($4)
      d_enabled[key]=norm_enabled($5)
      d_seen[key]=1
      next
    }
    {
      key=$1
      if (key=="") next
      a_allowed[key]=$2
      a_endpoint[key]=norm_endpoint($3)
      a_keep[key]=norm_keepalive($4)
      a_seen[key]=1
    }
    END {
      add=rem=upd=dis=0
      for (k in d_seen) {
        if (d_enabled[k]=="0") {
          if (k in a_seen) {
            print "DISABLE", k, d_allowed[k], d_endpoint[k], d_keep[k], d_enabled[k] >> plan
            dis++
          }
          continue
        }
        if (!(k in a_seen)) {
          print "ADD", k, d_allowed[k], d_endpoint[k], d_keep[k], d_enabled[k] >> plan
          add++
          continue
        }
        if (d_allowed[k] != a_allowed[k] || d_endpoint[k] != a_endpoint[k] || d_keep[k] != a_keep[k]) {
          print "UPDATE", k, d_allowed[k], d_endpoint[k], d_keep[k], d_enabled[k] >> plan
          upd++
        }
      }
      for (k in a_seen) {
        if (!(k in d_seen)) {
          print "REMOVE", k, a_allowed[k], a_endpoint[k], a_keep[k], "1" >> plan
          rem++
        }
      }
      total=add+rem+upd+dis
      print add, rem, upd, dis, total
    }
  ' "$desired_file" "$actual_file")"; then
    log "ERROR: failed to compute diff plan."
    return 15
  fi

  if [[ -s "$plan_tmp" ]]; then
    if ! sort -t $'\t' -k1,1 -k2,2 "$plan_tmp" > "$plan_file"; then
      log "ERROR: failed to sort plan file."
      return 16
    fi
  else
    : > "$plan_file"
  fi
  rm -f "$plan_tmp"

  local add=0 rem=0 upd=0 dis=0 total=0
  if [[ -n "$counts_line" ]]; then
    read -r add rem upd dis total <<< "$counts_line"
  fi

  {
    echo "Stage 3.5 diff report"
    echo "Desired: $desired_file"
    echo "Actual:  $actual_file"
    echo "Plan:    $plan_file"
    echo "Generated_UTC: $(date -u +'%Y-%m-%d %H:%M:%S')"
    echo
    echo "Summary:"
    echo "ADD=$add"
    echo "REMOVE=$rem"
    echo "UPDATE=$upd"
    echo "DISABLE=$dis"
    echo "TOTAL_CHANGES=$total"
    if [[ "$total" -eq 0 ]]; then
      echo "NO_CHANGES"
    fi
    echo
  } > "$diff_file"

  PLAN_FILE="$plan_file"
  write_section "$diff_file" "[only_in_desired] (ADD)" "ADD"
  write_section "$diff_file" "[only_in_actual] (REMOVE)" "REMOVE"
  write_section "$diff_file" "[in_both_but_different] (UPDATE)" "UPDATE"
  write_section "$diff_file" "[disabled_in_desired] (DISABLE)" "DISABLE"

  summary_kv "DESIRED_FILE" "$desired_file"
  summary_kv "ACTUAL_FILE" "$actual_file"
  summary_kv "DIFF_FILE" "$diff_file"
  summary_kv "PLAN_FILE" "$plan_file"
  summary_kv "ADD" "$add"
  summary_kv "REMOVE" "$rem"
  summary_kv "UPDATE" "$upd"
  summary_kv "DISABLE" "$dis"
  summary_kv "TOTAL_CHANGES" "$total"

  local diff_status
  if [[ "$total" -eq 0 ]]; then
    diff_status="NO_CHANGES"
  else
    diff_status="CHANGES_PENDING"
  fi
  summary_kv "DIFF_STATUS" "$diff_status"

  update_state "STAGE35_DESIRED_FILE" "$desired_file"
  update_state "STAGE35_ACTUAL_FILE" "$actual_file"
  update_state "STAGE35_DIFF_FILE" "$diff_file"
  update_state "STAGE35_PLAN_FILE" "$plan_file"
  update_state "STAGE35_DIFF_REPORT" "$REPORT_FILE"
  update_state "STAGE35_ADD_COUNT" "$add"
  update_state "STAGE35_REMOVE_COUNT" "$rem"
  update_state "STAGE35_UPDATE_COUNT" "$upd"
  update_state "STAGE35_DISABLE_COUNT" "$dis"
  update_state "STAGE35_TOTAL_CHANGES" "$total"
  update_state "STAGE35_DIFF_STATUS" "$diff_status"
  update_state "STAGE35_LAST_TS" "$(date +'%Y-%m-%d_%H-%M-%S')"

  if [[ "$total" -eq 0 ]]; then
    return 0
  fi
  return 20
}

report_init "stage35_diff"

rc=0
{
  main "$@"
} || rc=$?

if [[ "$rc" -ne 0 && "$rc" -ne 20 ]]; then
  maybe_commit_report_on_fail "$rc"
fi
=======
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
>>>>>>> 68d3b6b (fix)
exit "$rc"
