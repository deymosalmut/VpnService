#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

# -----------------------------
# Config
# -----------------------------
APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"

# Укажи путь к .csproj (по умолчанию пытаемся найти один-единственный)
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

ensure_dotnet() {
  command -v dotnet >/dev/null 2>&1
}

ensure_dotnet_ef() {
  # Prefer tool-manifest local restore if present
  if dotnet ef --version >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f ".config/dotnet-tools.json" ]]; then
    dotnet tool restore >/dev/null 2>&1 || true
  fi

  dotnet ef --version >/dev/null 2>&1
}

# -----------------------------
# Main
# -----------------------------
report_init "stage34_migrations_check"

rc=0
{
  section "Stage 3.4 — Migrations CHECK (DB + EF) — preconditions"

  run_step "Load app DB env" bash -lc "source scripts/lib/appdb.sh && load_app_db_env '$APP_DB_ENV'"

  run_step "Check dotnet present" bash -lc "command -v dotnet && dotnet --info | head -n 30"
  run_step "Check psql present" bash -lc "command -v psql && psql --version"

  run_step "Check dotnet-ef present (or restore)" bash -lc "
    cd '$REPO_ROOT'
    if dotnet ef --version >/dev/null 2>&1; then
      dotnet ef --version
      exit 0
    fi
    if [[ -f .config/dotnet-tools.json ]]; then
      dotnet tool restore
      dotnet ef --version
      exit 0
    fi
    echo 'dotnet-ef missing and no tool-manifest found (.config/dotnet-tools.json).'
    echo 'Fix: add local tool manifest + dotnet-ef as repo tool, then rerun.'
    exit 10
  "

  CSPRJ="$(detect_csproj)"
  summary_kv "CSPROJ" "$CSPRJ"

  # DB connect test (stable app connect)
  run_step "DB app connect: SELECT 1" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -c 'select 1;'
  "

  # Read EF migrations from source
  run_step "EF migrations list (source)" bash -lc "
    cd '$REPO_ROOT'
    dotnet ef migrations list --project '$CSPRJ' --no-build
  "

  # Read applied migrations from DB (__EFMigrationsHistory), handle missing table
  run_step "DB applied migrations (__EFMigrationsHistory)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    psql_app -Atc 'select migrationid from "__EFMigrationsHistory" order by migrationid;' || true
  "

  section "Compute pending migrations (source minus applied)"

  # Build pending list inside a single bash -lc to keep env/paths clean
  run_step_tee "Pending migrations detection + idempotent script generation" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    CSPRJ='$CSPRJ'

    src_file=\"/tmp/ef_migrations_source_\$\$.txt\"
    db_file=\"/tmp/ef_migrations_db_\$\$.txt\"
    pending_file=\"/tmp/ef_migrations_pending_\$\$.txt\"

    # Source: take lines that look like migration ids (start with digits)
    dotnet ef migrations list --project \"\$CSPRJ\" --no-build \
      | sed -n 's/^\\([0-9]\\{14\\}.*\\)$/\\1/p' > \"\$src_file\"

    # DB: may not exist yet; treat as empty if query fails
    (psql_app -Atc 'select migrationid from "__EFMigrationsHistory" order by migrationid;' || true) \
      | sed '/^\\s*$/d' > \"\$db_file\"

    # Pending = in source but not in db
    comm -23 <(sort \"\$src_file\") <(sort \"\$db_file\") > \"\$pending_file\" || true

    echo \"SOURCE migrations count: \$(wc -l < \"\$src_file\" | tr -d ' ')\"
    echo \"APPLIED migrations count: \$(wc -l < \"\$db_file\" | tr -d ' ')\"
    echo \"PENDING migrations count: \$(wc -l < \"\$pending_file\" | tr -d ' ')\"
    echo

    if [[ -s \"\$pending_file\" ]]; then
      echo \"Pending migrations:\"
      cat \"\$pending_file\"
      echo

      out_sql=\"$REPORT_DIR/ef_idempotent_\$(date +'%Y-%m-%d_%H-%M-%S').sql\"
      echo \"Generating idempotent SQL script -> \$out_sql\"
      dotnet ef migrations script --project \"\$CSPRJ\" --no-build --idempotent --output \"\$out_sql\"

      echo \"IDEMPOTENT_SQL=\$out_sql\"
      exit 20
    else
      echo \"No pending migrations.\"
      exit 0
    fi
  " || true

  # Interpret the previous step result: 0 = no pending, 20 = pending generated, others = fail
  last_rc=$?
  if [[ $last_rc -eq 0 ]]; then
    summary_kv "MIGRATIONS_PENDING" "0"
  elif [[ $last_rc -eq 20 ]]; then
    summary_kv "MIGRATIONS_PENDING" ">=1 (idempotent SQL generated)"
  else
    summary_kv "MIGRATIONS_PENDING" "UNKNOWN (error)"
    exit $last_rc
  fi

  section "Stage 3.4 — Migrations CHECK — DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
