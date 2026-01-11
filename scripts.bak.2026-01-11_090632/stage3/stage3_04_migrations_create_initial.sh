#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_LOCAL_ENV="${APP_LOCAL_ENV:-$REPO_ROOT/infra/local/app.env}"

# Default migration name (timestamped)
MIG_NAME="${MIG_NAME:-Initial_$(date +%Y%m%d_%H%M%S)}"

report_init "stage34_migrations_create_initial"

rc=0
{
  section "Stage 3.4 — CREATE INITIAL MIGRATION (controlled)"

  run_step "Load app DB env (normalize)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  if [[ -f "$APP_LOCAL_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$APP_LOCAL_ENV"
  fi
  : "${APP_CSPROJ:?APP_CSPROJ not set. Expected infra/local/app.env}"

  run_step "dotnet ef --version" bash -lc "cd '$REPO_ROOT' && dotnet ef --version"

  # Sanity: migrations list must work now
  run_step_tee "EF migrations list (before)" bash -lc "
    cd '$REPO_ROOT'
    dotnet ef migrations list --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --no-build
  "

  section "SAFETY GATE"
  log "This will CREATE a new migration in repo for project: $APP_CSPROJ"
  log "Migration name: $MIG_NAME"
  log "Type CREATE to continue."
  read -r -p "> " gate
  if [[ "$gate" != "CREATE" ]]; then
    log "Abort: gate not passed."
    exit 30
  fi

  # Create migration (no DB needed, but context factory reads env; keep env loaded)
  run_step_tee "dotnet ef migrations add $MIG_NAME" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations add '$MIG_NAME' --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ'
  "

  run_step_tee "EF migrations list (after)" bash -lc "
    cd '$REPO_ROOT'
    dotnet ef migrations list --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --no-build
  "

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
