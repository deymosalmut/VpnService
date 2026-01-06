#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

mkdir -p scripts/stage3 reports

# Minimal Stage 3.5 scripts (create files only; no runtime deps beyond existing libs)

cat >scripts/stage3/stage3_05_menu.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
STATE_FILE="$OUT_DIR/stage35_last_run.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
step_status=(); step_artifact=()
set_status(){ step_status["$1"]="$2"; step_artifact["$1"]="${3:-}"; }

print_table(){
  echo
  printf "%-28s | %-12s | %s\n" "STEP" "STATUS" "ARTIFACT"
  echo "--------------------------------------------------------------------------"
  for k in "1_DESIRED_DB" "2_ACTUAL_WG" "3_DIFF_PLAN" "4_APPLY"; do
    st="${step_status[$k]:-SKIP}"; art="${step_artifact[$k]:-}"
    color="$NC"; [[ "$st" == "OK" ]] && color="$GREEN"; [[ "$st" == "WARN" ]] && color="$YELLOW"; [[ "$st" == "FAIL" ]] && color="$RED"
    printf "%-28s | %b%-12s%b | %s\n" "$k" "$color" "$st" "$NC" "$art"
  done
  echo
}

save_state(){
  {
    echo "IFACE=$IFACE"
    echo "DESIRED_FILE=${DESIRED_FILE:-}"
    echo "ACTUAL_FILE=${ACTUAL_FILE:-}"
    echo "PLAN_FILE=${PLAN_FILE:-}"
    echo "DIFF_FILE=${DIFF_FILE:-}"
    echo "LAST_REPORT=${LAST_REPORT:-}"
    echo "UPDATED_UTC=$(date -u)"
  } >"$STATE_FILE"
}

run_cmd_capture(){
  local title="$1"; shift
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  echo "$out"
  LAST_REPORT="$(echo "$out" | grep -E 'Report:' | tail -n 1 | awk '{print $2}' || true)"
  return $rc
}

run_desired(){
  run_cmd_capture "desired" bash -lc "IFACE='$IFACE' bash scripts/stage3/stage3_05_desired_db_dump.sh"
  rc=$?
  DESIRED_FILE="$(echo "$out" | grep -E '^DESIRED_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  [[ $rc -eq 0 ]] && set_status "1_DESIRED_DB" "OK" "$DESIRED_FILE" || set_status "1_DESIRED_DB" "FAIL" "$LAST_REPORT"
  save_state
}

run_actual(){
  run_cmd_capture "actual" bash -lc "IFACE='$IFACE' bash scripts/stage3/stage3_05_actual_wg_dump.sh"
  rc=$?
  ACTUAL_FILE="$(echo "$out" | grep -E '^ACTUAL_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  [[ $rc -eq 0 ]] && set_status "2_ACTUAL_WG" "OK" "$ACTUAL_FILE" || set_status "2_ACTUAL_WG" "FAIL" "$LAST_REPORT"
  save_state
}

run_diff(){
  run_cmd_capture "diff" bash -lc "IFACE='$IFACE' DESIRED_FILE='${DESIRED_FILE:-}' ACTUAL_FILE='${ACTUAL_FILE:-}' bash scripts/stage3/stage3_05_diff.sh"
  rc=$?
  PLAN_FILE="$(echo "$out" | grep -E '^PLAN_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  DIFF_FILE="$(echo "$out" | grep -E '^DIFF_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  if [[ $rc -eq 0 ]]; then set_status "3_DIFF_PLAN" "OK" "$DIFF_FILE"
  elif [[ $rc -eq 20 ]]; then set_status "3_DIFF_PLAN" "WARN" "$DIFF_FILE"
  else set_status "3_DIFF_PLAN" "FAIL" "$LAST_REPORT"
  fi
  save_state
  return $rc
}

run_apply(){
  run_cmd_capture "apply" bash -lc "IFACE='$IFACE' PLAN_FILE='${PLAN_FILE:-}' bash scripts/stage3/stage3_05_reconcile_apply.sh"
  rc=$?
  [[ $rc -eq 0 ]] && set_status "4_APPLY" "OK" "$LAST_REPORT" || set_status "4_APPLY" "FAIL" "$LAST_REPORT"
  save_state
}

menu(){
  echo "Stage 3.5 Menu (IFACE=$IFACE)"
  echo "1) Desired DB dump"
  echo "2) Actual WG dump"
  echo "3) Diff/Plan"
  echo "4) Reconcile APPLY"
  echo "5) Run ALL"
  echo "0) Exit"
  read -r -p "> " c
  case "$c" in
    1) run_desired; print_table ;;
    2) run_actual; print_table ;;
    3) run_diff || true; print_table ;;
    4) run_apply; print_table ;;
    5) run_desired; run_actual; run_diff || true; print_table ;;
    0) exit 0 ;;
    *) echo "Unknown option" ;;
  esac
}

while true; do menu; done
SH

cat >scripts/stage3/stage3_05_desired_db_dump.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"
source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"
APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"

report_init "stage35_desired_db_dump"
rc=0
{
  section "Stage 3.5 — DESIRED (DB) dump (read-only)"
  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER\"
  "

  chosen="$(bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select schemaname||'.'||tablename
      from pg_tables
      where schemaname not in ('pg_catalog','information_schema')
        and tablename='peers'
      order by (schemaname='public') desc
      limit 1;
    \"
  " | tr -d '[:space:]' || true)"

  [[ -n "$chosen" ]] || { log "FAIL: table peers not found"; exit 12; }
  log "OK peers table: $chosen"

  out="$OUT_DIR/stage35_desired_$(date +%Y-%m-%d_%H-%M-%S).tsv"
  run_step_tee "Export desired TSV" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -AtF \$'\\t' -c \"select public_key::text, allowed_ips::text, ''::text, ''::text, 1 from $chosen order by public_key;\" > '$out'
    wc -l '$out'
  "

  section "Summary"
  log "DESIRED_FILE=$out"
} || rc=$?
maybe_commit_report_on_fail "$rc"
exit "$rc"
SH

cat >scripts/stage3/stage3_05_actual_wg_dump.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"
source "scripts/lib/report.sh"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"

report_init "stage35_actual_wg_dump"
rc=0
{
  section "Stage 3.5 — ACTUAL (WG) dump (read-only)"
  out="$OUT_DIR/stage35_actual_$(date +%Y-%m-%d_%H-%M-%S).tsv"
  run_step_tee "wg dump -> TSV" bash -lc "
    set -Eeuo pipefail
    wg show '$IFACE' dump | tail -n +2 | awk -v OFS='\t' 'NF>=5{print \$1,\$4,\$3,\$5,1}' > '$out'
    wc -l '$out'
  "
  section "Summary"
  log "ACTUAL_FILE=$out"
} || rc=$?
maybe_commit_report_on_fail "$rc"
exit "$rc"
SH

cat >scripts/stage3/stage3_05_diff.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"
source "scripts/lib/report.sh"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
DESIRED_FILE="${DESIRED_FILE:-}"
ACTUAL_FILE="${ACTUAL_FILE:-}"

report_init "stage35_diff"
rc=0
{
  section "Stage 3.5 — DIFF/PLAN (read-only)"
  [[ -n "$DESIRED_FILE" ]] || DESIRED_FILE="$(ls -1t "$OUT_DIR"/stage35_desired_*.tsv 2>/dev/null | head -n 1 || true)"
  [[ -n "$ACTUAL_FILE"  ]] || ACTUAL_FILE="$(ls -1t "$OUT_DIR"/stage35_actual_*.tsv 2>/dev/null | head -n 1 || true)"
  log "DESIRED_FILE=$DESIRED_FILE"
  log "ACTUAL_FILE=$ACTUAL_FILE"
  [[ -f "$DESIRED_FILE" ]] || exit 10
  [[ -f "$ACTUAL_FILE"  ]] || exit 11

  diff_txt="$OUT_DIR/stage35_diff_$(date +%Y-%m-%d_%H-%M-%S).txt"
  plan_tsv="$OUT_DIR/stage35_plan_$(date +%Y-%m-%d_%H-%M-%S).tsv"

  run_step_tee "Compute plan" bash -lc "
    set -Eeuo pipefail
    desired='$DESIRED_FILE'; actual='$ACTUAL_FILE'; plan='$plan_tsv'; diff='$diff_txt'
    awk -F'\t' 'NF>=2{print \$1}' \"\$desired\" | sort > /tmp/s35_d_\$\$.txt
    awk -F'\t' 'NF>=2{print \$1}' \"\$actual\"  | sort > /tmp/s35_a_\$\$.txt
    comm -23 /tmp/s35_d_\$\$.txt /tmp/s35_a_\$\$.txt | awk '{print \"ADD\\t\"\$1}' > \"\$plan\" || true
    comm -13 /tmp/s35_d_\$\$.txt /tmp/s35_a_\$\$.txt | awk '{print \"REMOVE\\t\"\$1}' >> \"\$plan\" || true
    total=\$(wc -l <\"\$plan\" | tr -d ' ')
    echo \"PLAN_FILE=\$plan\"
    echo \"DIFF_FILE=\$diff\"
    echo \"TOTAL_CHANGES=\$total\"
    if [[ \$total -gt 0 ]]; then echo \"CHANGES_PENDING=YES\"; exit 20; else echo \"CHANGES_PENDING=NO\"; exit 0; fi
  " || true

  section "Summary"
} || rc=$?
maybe_commit_report_on_fail "$rc"
exit "$rc"
SH

cat >scripts/stage3/stage3_05_reconcile_apply.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"
source "scripts/lib/report.sh"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
PLAN_FILE="${PLAN_FILE:-}"

report_init "stage35_reconcile_apply"
rc=0
{
  section "Stage 3.5 — RECONCILE APPLY (controlled)"
  [[ -n "$PLAN_FILE" ]] || PLAN_FILE="$(ls -1t "$OUT_DIR"/stage35_plan_*.tsv 2>/dev/null | head -n 1 || true)"
  log "IFACE=$IFACE"
  log "PLAN_FILE=$PLAN_FILE"
  [[ -f "$PLAN_FILE" ]] || exit 10

  total="$(wc -l <"$PLAN_FILE" | tr -d ' ' || echo 0)"
  log "TOTAL=$total"
  [[ $total -gt 0 ]] || { log "OK no changes"; exit 0; }

  section "SAFETY GATE"
  log "Type APPLY to continue."
  read -r -p "> " gate
  [[ "$gate" == "APPLY" ]] || exit 30

  while IFS=$'\t' read -r action pub; do
    [[ -n "${action:-}" && -n "${pub:-}" ]] || continue
    if [[ "$action" == "REMOVE" ]]; then
      run_step_tee "wg remove $pub" bash -lc "wg set '$IFACE' peer '$pub' remove"
    fi
    # NOTE: ADD requires allowed-ips; minimal bootstrap doesn't apply ADD.
  done <"$PLAN_FILE"

  section "Summary"
  log "DONE"
} || rc=$?
maybe_commit_report_on_fail "$rc"
exit "$rc"
SH

chmod +x scripts/stage3/stage3_05_*.sh
echo "OK created:"
ls -la scripts/stage3 | grep stage3_05_
