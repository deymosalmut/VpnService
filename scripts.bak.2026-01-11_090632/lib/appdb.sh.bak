#!/usr/bin/env bash
set -Eeuo pipefail

# Loads infra/local/app-db.env (gitignored) and validates required vars.
load_app_db_env() {
  local env_file="${1:-/opt/vpn-service/infra/local/app-db.env}"
  if [[ ! -f "$env_file" ]]; then
    echo "ERROR: app-db env file not found: $env_file" >&2
    return 2
  fi

  # shellcheck disable=SC1090
  source "$env_file"

  : "${PG_HOST:?PG_HOST missing in app-db.env}"
  : "${PG_PORT:?PG_PORT missing in app-db.env}"
  : "${PG_DATABASE:?PG_DATABASE missing in app-db.env}"
  : "${PG_USER:?PG_USER missing in app-db.env}"
  : "${PG_PASSWORD:?PG_PASSWORD missing in app-db.env}"

  export PG_HOST PG_PORT PG_DATABASE PG_USER PG_PASSWORD
}

app_conn_str() {
  # EF Core Npgsql connection string
  echo "Host=$PG_HOST;Port=$PG_PORT;Database=$PG_DATABASE;Username=$PG_USER;Password=$PG_PASSWORD;Include Error Detail=true"
}

psql_app() {
  PGPASSWORD="$PG_PASSWORD" psql \
    -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" \
    -v ON_ERROR_STOP=1 \
    "$@"
}
