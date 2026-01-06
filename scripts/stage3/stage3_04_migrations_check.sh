#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_LOCAL_ENV="${APP_LOCAL_ENV:-$REPO_ROOT/infra/local/app.env}"
CTX="${CTX:-VpnDbContext}"

report_init "stage34_migrations_check"

rc=0
{
  section "Stage 3.4 — MIGRATIONS CHECK"

  run_step "Load app DB env (normalize PG_DB/PG_DATABASE)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  if [[ -f "$APP_LOCAL_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$APP_LOCAL_ENV"
  fi
  : "${APP_CSPROJ:?APP_CSPROJ not set. Expected: $APP_LOCAL_ENV}"

  run_step "dotnet ef --version" bash -lc "cd '$REPO_ROOT' && dotnet ef --version"

  run_step "DB app connect: SELECT 1" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select 1;'
  "

  # This call is informational; it should not fail the stage.
  run_step_tee "EF migrations list (informational; WARN-only if fails)" bash -lc "
    set +e
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations list --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --no-build
    exit 0
  "

  # Compute pending using source list + applied history
  section "Compute pending + generate idempotent SQL if needed"
  run_step_tee "Compute pending" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'

    src=/tmp/ef_src_$$.txt
    db=/tmp/ef_db_$$.txt
    pending=/tmp/ef_pending_$$.txt

    # Source migrations (strip '(Pending)' marker)
    dotnet ef migrations list --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --no-build \
      | sed -n 's/^\\([0-9]\\{14\\}[^ ]*\\).*/\\1/p' > \"\$src\"

    # Applied migrations (history may not exist on fresh DB; treat as empty)
    (psql_app -Atc 'select \"MigrationId\" from \"__EFMigrationsHistory\" order by \"MigrationId\";' 2>/dev/null || true) \
      | sed '/^\\s*$/d' > \"\$db\"

    comm -23 <(sort \"\$src\") <(sort \"\$db\") > \"\$pending\" || true

    echo \"SOURCE_COUNT=\$(wc -l <\"\$src\" | tr -d ' ')\"
    echo \"APPLIED_COUNT=\$(wc -l <\"\$db\" | tr -d ' ')\"
    echo \"PENDING_COUNT=\$(wc -l <\"\$pending\" | tr -d ' ')\"

    if [[ -s \"\$pending\" ]]; then
      echo
      echo \"Pending migrations:\"
      cat \"\$pending\"

      out_sql=\"$REPO_ROOT/reports/ef_idempotent_$(date +%Y-%m-%d_%H-%M-%S).sql\"
      dotnet ef migrations script --project '$APP_CSPROJ' --startup-project '$APP_CSPROJ' --context '$CTX' --no-build --idempotent --output \"\$out_sql\"
      echo \"IDEMPOTENT_SQL=\$out_sql\"
      echo \"MIGRATIONS_PENDING=YES\"
    else
      echo \"MIGRATIONS_PENDING=NO\"
    fi
  "

  # Read MIGRATIONS_PENDING from report output (last occurrence)
  pending_flag="$(grep -E 'MIGRATIONS_PENDING=' "$REPORT_FILE" | tail -n 1 | cut -d= -f2 || true)"
  pending_flag="${pending_flag:-UNKNOWN}"

  section "Summary"
  if [[ "$pending_flag" == "NO" ]]; then
    log "OK Stage 3.4 migrations CHECK PASSED (no pending)."
  elif [[ "$pending_flag" == "YES" ]]; then
    log "FAIL Stage 3.4 migrations CHECK: pending migrations exist."
    rc=20
  else
    log "WARN Stage 3.4 migrations CHECK: could not determine pending state."
    rc="${rc:-21}"
  fi

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
