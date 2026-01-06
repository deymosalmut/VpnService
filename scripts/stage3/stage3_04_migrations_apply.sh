#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_CSPROJ="${APP_CSPROJ:-}"

detect_csproj() {
  if [[ -n "${APP_CSPROJ:-}" && -f "$APP_CSPROJ" ]]; then
    echo "$APP_CSPROJ"
    return 0
  fi
  local found
  found="$(find . -maxdepth 4 -name "*.csproj" | head -n 2 || true)"
  local count
  count="$(echo "$found" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
  if [[ "$count" -ne 1 ]]; then
    echo "ERROR: Cannot auto-detect unique .csproj. Set APP_CSPROJ explicitly." >&2
    echo "Candidates:" >&2
    echo "$found" >&2
    return 3
  fi
  echo "$found"
}

report_init "stage34_migrations_apply"

rc=0
{
  section "Stage 3.4 — MIGRATIONS APPLY (controlled)"

  run_step "Load app DB env" bash -lc "source scripts/lib/appdb.sh && load_app_db_env '$APP_DB_ENV'"
  run_step "Check dotnet-ef available" bash -lc "
    cd '$REPO_ROOT'
    if dotnet ef --version >/dev/null 2>&1; then dotnet ef --version; exit 0; fi
    if [[ -f .config/dotnet-tools.json ]]; then dotnet tool restore && dotnet ef --version; exit 0; fi
    echo 'dotnet-ef missing and no tool-manifest found.'
    exit 10
  "

  CSPRJ="$(detect_csproj)"
  summary_kv "CSPROJ" "$CSPRJ"

  # Stable DB connect test
  run_step "DB app connect: SELECT 1" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -c 'select 1;'
  "

  section "SAFETY GATE"
  log "This will APPLY EF migrations to DB '$PG_DATABASE' on $PG_HOST:$PG_PORT as user '$PG_USER'."
  log "To continue, type: APPLY"
  read -r -p "> " gate
  if [[ "$gate" != "APPLY" ]]; then
    log "Abort: gate not passed."
    exit 30
  fi

  # Apply using explicit connection string (no reliance on appsettings)
  run_step_tee "EF database update (apply migrations)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    CSPRJ='$CSPRJ'
    CONN=\"\$(app_conn_str)\"
    echo \"Using connection: Host=\$PG_HOST;Port=\$PG_PORT;Database=\$PG_DATABASE;Username=\$PG_USER;Password=***\"
    dotnet ef database update --project \"\$CSPRJ\" --no-build --connection \"\$CONN\"
  "

  run_step "DB applied migrations (__EFMigrationsHistory) after apply" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select migrationid from "__EFMigrationsHistory" order by migrationid;'
  "

  section "Stage 3.4 — MIGRATIONS APPLY — DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
