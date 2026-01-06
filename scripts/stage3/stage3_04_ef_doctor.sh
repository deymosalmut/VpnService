#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_LOCAL_ENV="${APP_LOCAL_ENV:-$REPO_ROOT/infra/local/app.env}"

report_init "stage34_ef_doctor"

rc=0
{
  section "EF Doctor — environment"
  run_step "dotnet ef --version" bash -lc "cd '$REPO_ROOT' && dotnet ef --version"
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

  section "EF Doctor — list candidate projects"
  # Prefer known likely projects first
  candidates=(
    "./VpnService.Api/VpnService.Api.csproj"
    "./VpnService.Infrastructure/VpnService.Infrastructure.csproj"
    "./VpnService.Infrastructure.Abstractions/VpnService.Infrastructure.Abstractions.csproj"
    "./VpnService.Application/VpnService.Application.csproj"
  )

  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      log "CANDIDATE: $p"
    else
      log "SKIP missing: $p"
    fi
  done

  section "EF Doctor — try migrations list per candidate (FULL OUTPUT)"
  ok=0
  for p in "${candidates[@]}"; do
    [[ -f "$p" ]] || continue
    section "TRY: dotnet ef migrations list --project '$p' --startup-project '$p'"
    set +e
    bash -lc "cd '$REPO_ROOT' && dotnet ef migrations list --project '$p' --startup-project '$p' --no-build" 2>&1 | tee -a "$REPORT_FILE"
    r=${PIPESTATUS[0]}
    set -e
    log "EXIT_CODE: $r"
    if [[ $r -eq 0 ]]; then
      log "OK EF works with: $p"
      ok=1
      break
    fi
  done

  if [[ $ok -ne 1 ]]; then
    log "FAIL: EF migrations list failed for all candidates."
    exit 20
  fi

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
