#!/usr/bin/env bash
set -Eeuo pipefail
REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
report_init "stage35_db_doctor"
rc=0
{
  section "Stage 3.5 — DB DOCTOR (read-only schema inspection)"

  run_step "Load app DB env" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  run_step_tee "List non-system tables (schema.table) [top 200]" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select table_schema||'.'||table_name
      from information_schema.tables
      where table_type='BASE TABLE'
        and table_schema not in ('pg_catalog','information_schema')
      order by table_schema, table_name
      limit 200;
    \"
  "

  run_step_tee "Find columns like public_key / allowed_ips / endpoint / keepalive (top 400)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      select table_schema||'.'||table_name||'|'||column_name||'|'||data_type
      from information_schema.columns
      where table_schema not in ('pg_catalog','information_schema')
        and (
          lower(column_name) like '%public%key%'
          or lower(column_name) like '%allowed%ip%'
          or lower(column_name) like '%endpoint%'
          or lower(column_name) like '%keepalive%'
          or lower(column_name) like '%preshared%'
        )
      order by table_schema, table_name, ordinal_position
      limit 400;
    \"
  "

  run_step_tee "Tables that contain a public_key-ish column (grouped) [top 100]" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc \"
      with c as (
        select table_schema, table_name,
          max(case when lower(column_name) like '%public%key%' then 1 else 0 end) as has_pub,
          max(case when lower(column_name) like '%allowed%ip%' then 1 else 0 end) as has_allowed,
          max(case when lower(column_name) like '%endpoint%' then 1 else 0 end) as has_ep,
          max(case when lower(column_name) like '%keepalive%' then 1 else 0 end) as has_ka
        from information_schema.columns
        where table_schema not in ('pg_catalog','information_schema')
        group by table_schema, table_name
      )
      select table_schema||'.'||table_name||' pub='||has_pub||' allowed='||has_allowed||' ep='||has_ep||' ka='||has_ka
      from c
      where has_pub=1 or has_allowed=1
      order by has_pub desc, has_allowed desc, table_schema, table_name
      limit 100;
    \"
  "

  section "EF (optional) — dbcontext list/info (best-effort)"
  run_step_tee "dotnet ef dbcontext list (best-effort)" bash -lc "
    cd '$REPO_ROOT'
    if dotnet ef dbcontext list --project './VpnService.Infrastructure/VpnService.Infrastructure.csproj' --startup-project './VpnService.Infrastructure/VpnService.Infrastructure.csproj' --context 'VpnDbContext' >/dev/null 2>&1; then
      dotnet ef dbcontext list --project './VpnService.Infrastructure/VpnService.Infrastructure.csproj' --startup-project './VpnService.Infrastructure/VpnService.Infrastructure.csproj'
      exit 0
    fi
    echo 'INFO: dotnet ef dbcontext list failed (ok).'
    exit 0
  "

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
