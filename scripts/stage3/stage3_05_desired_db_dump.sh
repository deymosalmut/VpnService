#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/reports}"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }

report_init "stage35_desired_db_dump"
rc=0
{
  section "Stage 3.5 — DESIRED (DB) dump (read-only)"
  out="$OUT_DIR/stage35_desired_$(ts).tsv"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER\"
  "

  run_step_tee "Export desired TSV from public.\"VpnPeers\" (pub<TAB>allowed<TAB>endpoint<TAB>keepalive<TAB>enabled)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'

    psql_app -v ON_ERROR_STOP=1 -Atc \"
      select
        \\\"PublicKey\\\" || E'\\t' ||
        (\\\"AssignedIp\\\" || '/32') || E'\\t' ||
        '' || E'\\t' ||
        '0' || E'\\t' ||
        (case when coalesce(\\\"Status\\\",0) <> 0 then '1' else '0' end)
      from public.\\\"VpnPeers\\\"
      order by \\\"PublicKey\\\";
    \" > '$out'

    wc -l '$out'
  "

  section "Summary"
  log "DESIRED_FILE=$out"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
