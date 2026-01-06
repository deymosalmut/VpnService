#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"

report_init "stage35_db_show_servers"
rc=0
{
  section "Stage 3.5 — DB: show VpnServers + FK check (read-only)"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT\"
  "

  run_step_tee "VpnServers count" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select count(*) from public.\"VpnServers\";'
  "

  run_step_tee "VpnServers rows (top 20): Id|Name|Gateway|Network" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select
        \\\"Id\\\"::text||'|'||
        coalesce(\\\"Name\\\",  '')||'|'||
        coalesce(\\\"Gateway\\\",'')||'|'||
        coalesce(\\\"Network\\\",'')
      from public.\\\"VpnServers\\\"
      order by \\\"CreatedAt\\\" desc
      limit 20;
    \"
  "

  run_step_tee "FK check: does peer.VpnServerId exist in VpnServers?" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select count(*)
      from public.\\\"VpnServers\\\"
      where \\\"Id\\\" = (select \\\"VpnServerId\\\" from public.\\\"VpnPeers\\\" limit 1);
    \"
  "

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
