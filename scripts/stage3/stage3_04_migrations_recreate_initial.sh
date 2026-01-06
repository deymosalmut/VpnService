#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"
ts(){ date +"%Y-%m-%d_%H-%M-%S"; }
REPORT_FILE="$REPORT_DIR/report_stage34_migrations_recreate_initial_$(ts).log"
: >"$REPORT_FILE"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_LOCAL_ENV="${APP_LOCAL_ENV:-$REPO_ROOT/infra/local/app.env}"
CTX="${CTX:-VpnDbContext}"
OUT_DIR="${OUT_DIR:-Migrations}"
MIG_NAME="${MIG_NAME:-Initial_$(date +%Y%m%d_%H%M%S)}"

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

main() {
  section "Stage 3.4 — RECREATE INITIAL MIGRATION (PendingModelChanges fix)"
  log "REPO_ROOT=$REPO_ROOT"
  log "CTX=$CTX"
  log "OUT_DIR=$OUT_DIR"
  log "NEW_MIG_NAME=$MIG_NAME"
  log ""

  if [[ ! -f "$APP_DB_ENV" ]]; then
    log "FAIL missing env: $APP_DB_ENV"
    exit 10
  fi

  # load env into this shell + export for child
  source "$REPO_ROOT/scripts/lib/appdb.sh"
  load_app_db_env "$APP_DB_ENV"

  if [[ -f "$APP_LOCAL_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$APP_LOCAL_ENV"
  fi
  : "${APP_CSPROJ:?APP_CSPROJ not set. Expected: $APP_LOCAL_ENV}"

  run_tee "dotnet ef --version" bash -lc "cd '$REPO_ROOT' && dotnet ef --version"

  section "Current migrations files in $OUT_DIR (for visibility)"
  (ls -la "$REPO_ROOT/VpnService.Infrastructure/$OUT_DIR" 2>/dev/null || true) | tee -a "$REPORT_FILE"

  section "SAFETY GATE"
  log "This will REMOVE the last migration and DELETE migration files in $OUT_DIR, then CREATE a fresh initial migration."
  log "Project: $APP_CSPROJ"
  log "Context: $CTX"
  log "Type RECREATE to continue."
  read -r -p "> " gate
  if [[ "$gate" != "RECREATE" ]]; then
    log "Abort: gate not passed."
    exit 30
  fi

  # 1) Try EF remove (best-effort)
  run_tee "dotnet ef migrations remove (force)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations remove --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --force
  " || true

  # 2) Remove migration files in output dir (we keep snapshot if it will be regenerated anyway)
  #    For initial MVP, safest is to wipe the Migrations folder inside Infrastructure and regenerate.
  run_tee "Wipe migrations folder (Infrastructure/$OUT_DIR) except keep dir" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    dir='./VpnService.Infrastructure/$OUT_DIR'
    if [[ -d \"\$dir\" ]]; then
      find \"\$dir\" -type f -name '*.cs' -delete
      echo \"OK wiped: \$dir/*.cs\"
    else
      mkdir -p \"\$dir\"
      echo \"OK created: \$dir\"
    fi
  "

  # 3) Recreate initial migration
  run_tee "dotnet ef migrations add $MIG_NAME (fresh)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations add '$MIG_NAME' --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --output-dir '$OUT_DIR'
  "

  run_tee "dotnet ef migrations list (after)" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations list --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --no-build
  "

  section "DONE"
  log "Done. Report saved: $REPORT_FILE"
}

main "$@"
