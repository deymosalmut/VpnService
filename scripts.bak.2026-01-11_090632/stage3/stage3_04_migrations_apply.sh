#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$REPORT_DIR/report_stage34_migrations_apply_$(ts).log"
: >"$REPORT_FILE"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_LOCAL_ENV="${APP_LOCAL_ENV:-$REPO_ROOT/infra/local/app.env}"
CTX="${CTX:-VpnDbContext}"

log(){ echo -e "$*" | tee -a "$REPORT_FILE"; }
hr(){ log "----------------------------------------------------------------"; }
section(){ hr; log ">>> $*"; hr; }

run_tee() {
  local title="$1"; shift
  section "$title"
  log "CMD: $*"
  set +e
  ( "$@" ) 2>&1 | tee -a "$REPORT_FILE"
  local rc=${PIPESTATUS[0]}
  set -e
  log "STATUS: $rc"
  return $rc
}

commit_report_on_fail() {
  local rc="$1"
  if [[ $rc -eq 0 ]]; then
    log "Done. Report saved: $REPORT_FILE"
    exit 0
  fi
  hr
  log "FAIL detected. Report: $REPORT_FILE"
  read -r -p "Commit report to git? (yes/no): " ans
  if [[ "${ans,,}" == "yes" ]]; then
    git add -f "$REPORT_FILE" >/dev/null 2>&1 || true
    git commit -m "report: $(basename "$REPORT_FILE")" >/dev/null 2>&1 || true
    log "Report committed."
  else
    log "Report NOT committed."
  fi
  exit "$rc"
}

rc=0
{
  section "Stage 3.4 — MIGRATIONS APPLY (build + update)"
  log "REPO_ROOT=$REPO_ROOT"
  log "REPORT_FILE=$REPORT_FILE"
  log "CTX=$CTX"
  log ""

  [[ -f "$APP_DB_ENV" ]] || { log "FAIL missing env: $APP_DB_ENV"; exit 10; }
  # shellcheck disable=SC1090
  source "$REPO_ROOT/scripts/lib/appdb.sh"
  load_app_db_env "$APP_DB_ENV"

  if [[ -f "$APP_LOCAL_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$APP_LOCAL_ENV"
  fi
  : "${APP_CSPROJ:?APP_CSPROJ not set. Expected: $APP_LOCAL_ENV}"

  run_tee "dotnet ef --version" bash -lc "cd '$REPO_ROOT' && dotnet ef --version"

  run_tee "DB app connect: SELECT 1" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select 1;'
  "

  run_tee "EF migrations list (source, explicit context)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations list --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX'
  "

  section "SAFETY GATE"
  log "Target DB: $PG_DATABASE @ $PG_HOST:$PG_PORT user=$PG_USER"
  log "Project: $APP_CSPROJ"
  log "Context: $CTX"
  log "This step will BUILD and APPLY migrations."
  log "Type APPLY to continue."
  read -r -p "> " gate
  if [[ "$gate" != "APPLY" ]]; then
    log "Abort: gate not passed."
    exit 30
  fi

  run_tee "dotnet build (required to avoid PendingModelChanges with --no-build)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    dotnet build '$APP_CSPROJ' -c Debug
  "

  run_tee "EF database update (apply migrations) [NO --no-build]" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    CONN=\"\$(app_conn_str)\"
    dotnet ef database update --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --connection \"\$CONN\"
  "

  run_tee "DB: __EFMigrationsHistory after apply" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select "MigrationId", "ProductVersion" from "__EFMigrationsHistory" order by "MigrationId";'
  "

  section "Summary"
  log "OK migrations applied."
} || rc=$?

commit_report_on_fail "$rc"
