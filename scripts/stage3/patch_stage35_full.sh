#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

# ---------- stage3_05_menu.sh (fix associative arrays + state tracking) ----------
cat >scripts/stage3/stage3_05_menu.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
cd "$REPO_ROOT"

OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
STATE_FILE="$OUT_DIR/stage35_last_run.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

declare -A step_status
declare -A step_artifact

set_status(){ local k="$1"; local st="$2"; local art="${3:-}"; step_status["$k"]="$st"; step_artifact["$k"]="$art"; }

print_table(){
  echo
  printf "%-28s | %-12s | %s\n" "STEP" "STATUS" "ARTIFACT"
  echo "--------------------------------------------------------------------------"
  for k in "1_DESIRED_DB" "2_ACTUAL_WG" "3_DIFF_PLAN" "4_APPLY"; do
    local st="${step_status[$k]:-SKIP}"
    local art="${step_artifact[$k]:-}"
    local color="$NC"
    [[ "$st" == "OK"   ]] && color="$GREEN"
    [[ "$st" == "WARN" ]] && color="$YELLOW"
    [[ "$st" == "FAIL" ]] && color="$RED"
    printf "%-28s | %b%-12s%b | %s\n" "$k" "$color" "$st" "$NC" "$art"
  done
  echo
}

save_state(){
  mkdir -p "$OUT_DIR" || true
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
  local cmd="$*"
  set +e
  out="$(bash -lc "$cmd" 2>&1)"
  rc=$?
  set -e
  echo "$out"
  LAST_REPORT="$(echo "$out" | grep -E 'Report:' | tail -n 1 | awk '{print $2}' || true)"
  return $rc
}

run_desired(){
  run_cmd_capture "IFACE='$IFACE' bash scripts/stage3/stage3_05_desired_db_dump.sh"
  rc=$?
  DESIRED_FILE="$(echo "$out" | grep -E '^DESIRED_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  if [[ $rc -eq 0 ]]; then set_status "1_DESIRED_DB" "OK" "$DESIRED_FILE"; else set_status "1_DESIRED_DB" "FAIL" "${LAST_REPORT:-}"; fi
  save_state
}

run_actual(){
  run_cmd_capture "IFACE='$IFACE' bash scripts/stage3/stage3_05_actual_wg_dump.sh"
  rc=$?
  ACTUAL_FILE="$(echo "$out" | grep -E '^ACTUAL_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  if [[ $rc -eq 0 ]]; then set_status "2_ACTUAL_WG" "OK" "$ACTUAL_FILE"; else set_status "2_ACTUAL_WG" "FAIL" "${LAST_REPORT:-}"; fi
  save_state
}

run_diff(){
  run_cmd_capture "IFACE='$IFACE' DESIRED_FILE='${DESIRED_FILE:-}' ACTUAL_FILE='${ACTUAL_FILE:-}' bash scripts/stage3/stage3_05_diff.sh"
  rc=$?
  PLAN_FILE="$(echo "$out" | grep -E '^PLAN_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  DIFF_FILE="$(echo "$out" | grep -E '^DIFF_FILE=' | tail -n 1 | cut -d= -f2- || true)"
  if [[ $rc -eq 0 ]]; then
    set_status "3_DIFF_PLAN" "OK" "$DIFF_FILE"
  elif [[ $rc -eq 20 ]]; then
    set_status "3_DIFF_PLAN" "WARN" "$DIFF_FILE"
  else
    set_status "3_DIFF_PLAN" "FAIL" "${LAST_REPORT:-}"
  fi
  save_state
  return $rc
}

run_apply(){
  run_cmd_capture "IFACE='$IFACE' PLAN_FILE='${PLAN_FILE:-}' bash scripts/stage3/stage3_05_reconcile_apply.sh"
  rc=$?
  if [[ $rc -eq 0 ]]; then set_status "4_APPLY" "OK" "${LAST_REPORT:-}"; else set_status "4_APPLY" "FAIL" "${LAST_REPORT:-}"; fi
  save_state
}

menu(){
  echo "Stage 3.5 Menu (IFACE=$IFACE)"
  echo "1) Desired DB dump"
  echo "2) Actual WG dump"
  echo "3) Diff/Plan"
  echo "4) Reconcile APPLY"
  echo "5) Run ALL (1->3)"
  echo "0) Exit"
  echo
  read -r -p "> " c
  case "$c" in
    1) run_desired; print_table ;;
    2) run_actual;  print_table ;;
    3) run_diff || true; print_table ;;
    4) run_apply; print_table ;;
    5)
      run_desired
      run_actual
      if run_diff; then :; else
        rc=$?
        if [[ $rc -eq 20 ]]; then
          echo
          echo -e "${YELLOW}Changes pending. Run option 4 to apply.${NC}"
        fi
      fi
      print_table
      ;;
    0) exit 0 ;;
    *) echo "Unknown option" ;;
  esac
}

while true; do menu; done
SH
chmod +x scripts/stage3/stage3_05_menu.sh

# ---------- stage3_05_desired_db_dump.sh (auto-detect table + columns) ----------
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
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  section "Locate table that has columns public_key + allowed_ips"
  chosen="$(bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      with t as (
        select table_schema, table_name,
          max(case when column_name='public_key' then 1 else 0 end) as has_pub,
          max(case when column_name='allowed_ips' then 1 else 0 end) as has_allowed
        from information_schema.columns
        where table_schema not in ('pg_catalog','information_schema')
        group by table_schema, table_name
      )
      select table_schema||'.'||table_name
      from t
      where has_pub=1 and has_allowed=1
      order by (table_schema='public') desc, (table_name='peers') desc, table_schema, table_name
      limit 1;
    \"
  " | tr -d '[:space:]' || true)"

  if [[ -z "$chosen" ]]; then
    log "FAIL: cannot find any table with columns (public_key, allowed_ips)."
    section "DEBUG: candidates (top 50) with public_key"
    bash -lc "
      cd '$REPO_ROOT'
      source scripts/lib/appdb.sh
      load_app_db_env '$APP_DB_ENV'
      psql_app -Atc \"
        select table_schema||'.'||table_name
        from information_schema.columns
        where table_schema not in ('pg_catalog','information_schema')
          and column_name='public_key'
        group by table_schema, table_name
        order by 1
        limit 50;
      \"
    " 2>&1 | tee -a "$REPORT_FILE" || true
    exit 12
  fi

  log "OK chosen table: $chosen"

  cols="$(bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select column_name
      from information_schema.columns
      where table_schema = split_part('$chosen','.',1)
        and table_name   = split_part('$chosen','.',2)
      order by ordinal_position;
    \"
  " | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g' | sed 's/^ //;s/ $//' || true)"
  log "COLUMNS: $cols"

  endpoint_col=""; echo " $cols " | grep -q " endpoint " && endpoint_col="endpoint"
  ka_col=""
  for c in persistent_keepalive keepalive; do echo " $cols " | grep -q " $c " && ka_col="$c" && break; done
  enabled_col=""
  for c in enabled is_enabled active; do echo " $cols " | grep -q " $c " && enabled_col="$c" && break; done
  disabled_col=""
  for c in disabled is_disabled; do echo " $cols " | grep -q " $c " && disabled_col="$c" && break; done

  out="$OUT_DIR/stage35_desired_$(date +%Y-%m-%d_%H-%M-%S).tsv"
  section "Export desired TSV (pub<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled)"
  log "OUT=$out"

  sql="select
    public_key::text as public_key,
    allowed_ips::text as allowed_ips,
    "
  if [[ -n "$endpoint_col" ]]; then sql+="coalesce(${endpoint_col}::text,'') as endpoint,"; else sql+="''::text as endpoint,"; fi
  if [[ -n "$ka_col" ]]; then sql+="coalesce(${ka_col}::text,'') as keepalive,"; else sql+="''::text as keepalive,"; fi

  if [[ -n "$enabled_col" ]]; then
    sql+="case when coalesce(${enabled_col}::text,'') in ('t','true','1','yes','y') then 1 else 0 end as enabled"
  elif [[ -n "$disabled_col" ]]; then
    sql+="case when coalesce(${disabled_col}::text,'') in ('t','true','1','yes','y') then 0 else 1 end as enabled"
  else
    sql+="1 as enabled"
  fi

  sql+="
    from ${chosen}
    order by public_key;"

  run_step_tee "psql export" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -AtF \$'\\t' -c \"$sql\" > '$out'
    wc -l '$out'
  "

  section "Summary"
  log "DESIRED_TABLE=$chosen"
  log "DESIRED_FILE=$out"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
SH
chmod +x scripts/stage3/stage3_05_desired_db_dump.sh

# ---------- stage3_05_actual_wg_dump.sh (stable TSV + tabs) ----------
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
  section "Export actual TSV (pub<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled=1)"
  log "OUT=$out"

  run_step_tee "wg dump -> tsv" bash -lc "
    set -Eeuo pipefail
    wg show '$IFACE' dump | tail -n +2 | awk -v OFS=\$'\\t' 'NF>=5{print \$1,\$4,\$3,\$5,1}' > '$out'
    wc -l '$out'
  "

  section "Summary"
  log "ACTUAL_FILE=$out"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
SH
chmod +x scripts/stage3/stage3_05_actual_wg_dump.sh

# ---------- stage3_05_diff.sh (full plan: ADD/REMOVE/UPDATE/DISABLE) ----------
cat >scripts/stage3/stage3_05_diff.sh <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
IFACE="${IFACE:-wg1}"
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
  [[ -f "$DESIRED_FILE" ]] || { log "FAIL missing desired file"; exit 10; }
  [[ -f "$ACTUAL_FILE"  ]] || { log "FAIL missing actual file"; exit 11; }

  diff_txt="$OUT_DIR/stage35_diff_$(date +%Y-%m-%d_%H-%M-%S).txt"
  plan_tsv="$OUT_DIR/stage35_plan_$(date +%Y-%m-%d_%H-%M-%S).tsv"

  section "Compute plan"
  run_step_tee "plan build" bash -lc "
    set -Eeuo pipefail
    desired='$DESIRED_FILE'
    actual='$ACTUAL_FILE'
    plan='$plan_tsv'
    diff='$diff_txt'

    # normalize to 5 fields: pub allowed ep ka enabled
    awk -F'\t' 'NF>=2{
      pub=\$1; allowed=\$2; ep=(NF>=3?\$3:\"\"); ka=(NF>=4?\$4:\"\"); en=(NF>=5?\$5:1);
      print pub\"\\t\"allowed\"\\t\"ep\"\\t\"ka\"\\t\"en
    }' \"\$desired\" | sed '/^\\s*$/d' > /tmp/s35_desired_\$\$.tsv

    awk -F'\t' 'NF>=2{
      pub=\$1; allowed=\$2; ep=(NF>=3?\$3:\"\"); ka=(NF>=4?\$4:\"\"); en=(NF>=5?\$5:1);
      print pub\"\\t\"allowed\"\\t\"ep\"\\t\"ka\"\\t\"en
    }' \"\$actual\" | sed '/^\\s*$/d' > /tmp/s35_actual_\$\$.tsv

    awk -F'\t' '
      BEGIN{OFS=\"\\t\"}
      FNR==NR{
        d_allowed[\$1]=\$2; d_ep[\$1]=\$3; d_ka[\$1]=\$4; d_en[\$1]=\$5+0; d_seen[\$1]=1; next
      }
      {
        a_allowed[\$1]=\$2; a_ep[\$1]=\$3; a_ka[\$1]=\$4; a_seen[\$1]=1
      }
      END{
        add=rem=upd=dis=0;
        for(k in d_seen){
          en=d_en[k];
          if(en==0){
            if(a_seen[k]){
              print \"DISABLE\", k, d_allowed[k], d_ep[k], d_ka[k], 0 >> plan; dis++;
            }
            next;
          }
          if(!a_seen[k]){
            print \"ADD\", k, d_allowed[k], d_ep[k], d_ka[k], 1 >> plan; add++; next;
          }
          if(d_allowed[k]!=a_allowed[k] || d_ep[k]!=a_ep[k] || d_ka[k]!=a_ka[k]){
            print \"UPDATE\", k, d_allowed[k], d_ep[k], d_ka[k], 1 >> plan; upd++;
          }
        }
        for(k in a_seen){
          if(!d_seen[k]){
            print \"REMOVE\", k, a_allowed[k], a_ep[k], a_ka[k], 1 >> plan; rem++;
          }
        }

        total=add+rem+upd+dis;
        print \"SUMMARY add=\"add\" remove=\"rem\" update=\"upd\" disable=\"dis\" total=\"total > diff;
        print \"PLAN_FILE=\"plan;
        print \"DIFF_FILE=\"diff;
        print \"ADD=\"add\" REMOVE=\"rem\" UPDATE=\"upd\" DISABLE=\"dis\" TOTAL_CHANGES=\"total;
        if(total>0){ print \"CHANGES_PENDING=YES\"; exit 20 } else { print \"CHANGES_PENDING=NO\"; exit 0 }
      }
    ' /tmp/s35_desired_\$\$.tsv /tmp/s35_actual_\$\$.tsv
  " || true

  section "Artifacts"
  log "PLAN_FILE=$plan_tsv"
  log "DIFF_FILE=$diff_txt"

  # Determine pending from the report output
  pending="$(grep -E 'CHANGES_PENDING=' "$REPORT_FILE" | tail -n 1 | cut -d= -f2 || true)"

  section "Summary"
  if [[ "$pending" == "YES" ]]; then
    log "RESULT=CHANGES_PENDING"
    exit 20
  fi
  log "RESULT=NO_CHANGES"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
SH
chmod +x scripts/stage3/stage3_05_diff.sh

# ---------- stage3_05_reconcile_apply.sh (apply ADD/UPDATE/REMOVE/DISABLE) ----------
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
  [[ -f "$PLAN_FILE" ]] || { log "FAIL missing plan file"; exit 10; }

  addc="$(awk -F'\t' '$1=="ADD"{c++} END{print c+0}' "$PLAN_FILE" || true)"
  remc="$(awk -F'\t' '$1=="REMOVE"{c++} END{print c+0}' "$PLAN_FILE" || true)"
  updc="$(awk -F'\t' '$1=="UPDATE"{c++} END{print c+0}' "$PLAN_FILE" || true)"
  disc="$(awk -F'\t' '$1=="DISABLE"{c++} END{print c+0}' "$PLAN_FILE" || true)"
  total=$((addc+remc+updc+disc))

  section "Plan summary"
  log "ADD=$addc REMOVE=$remc UPDATE=$updc DISABLE=$disc TOTAL=$total"
  [[ $total -gt 0 ]] || { log "OK no changes to apply."; exit 0; }

  section "SAFETY GATE"
  log "Type APPLY to continue."
  read -r -p "> " gate
  [[ "$gate" == "APPLY" ]] || { log "Abort: gate not passed."; exit 30; }

  section "Apply wg set operations"
  while IFS=$'\t' read -r action pub allowed ep ka en; do
    [[ -n "${action:-}" && -n "${pub:-}" ]] || continue
    case "$action" in
      ADD|UPDATE)
        cmd=(wg set "$IFACE" peer "$pub" allowed-ips "$allowed")
        [[ -n "${ep:-}" && "$ep" != "(none)" ]] && cmd+=(endpoint "$ep")
        [[ -n "${ka:-}" && "$ka" != "0" ]] && cmd+=(persistent-keepalive "$ka")
        run_step_tee "wg set $action $pub" bash -lc "$(printf '%q ' "${cmd[@]}")"
        ;;
      REMOVE|DISABLE)
        run_step_tee "wg remove $pub" bash -lc "wg set '$IFACE' peer '$pub' remove"
        ;;
      *)
        log "WARN unknown action: $action"
        ;;
    esac
  done <"$PLAN_FILE"

  section "Post-apply verify: actual + diff"
  run_step_tee "actual dump" bash -lc "IFACE='$IFACE' bash scripts/stage3/stage3_05_actual_wg_dump.sh"
  set +e
  out="$(bash -lc "IFACE='$IFACE' bash scripts/stage3/stage3_05_diff.sh" 2>&1 | tee -a "$REPORT_FILE")"
  rc2=${PIPESTATUS[0]}
  set -e
  log "DIFF_RC=$rc2"
  if [[ $rc2 -eq 20 ]]; then
    log "FAIL: changes still pending after apply."
    exit 40
  fi
  [[ $rc2 -eq 0 ]] || { log "FAIL: diff failed after apply."; exit 41; }

  section "Summary"
  log "OK reconcile apply finished and verified NO_CHANGES."
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
SH
chmod +x scripts/stage3/stage3_05_reconcile_apply.sh

echo "OK patched Stage 3.5 scripts:"
ls -la scripts/stage3 | grep stage3_05_
