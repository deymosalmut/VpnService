#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"

report_init "stage35_db_doctor_vpnservers"
rc=0
{
  section "Stage 3.5 — DB DOCTOR: VpnServers schema + count (read-only)"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  run_step_tee "Describe public.\"VpnServers\" columns (name|type|nullable|default)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select column_name||'|'||data_type||'|'||is_nullable||'|'||coalesce(column_default,'')
      from information_schema.columns
      where table_schema='public' and table_name='VpnServers'
      order by ordinal_position;
    \"
  "

  run_step_tee "Count rows in public.\"VpnServers\"" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select count(*) from public.\"VpnServers\";'
  "

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
