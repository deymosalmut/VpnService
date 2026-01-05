#!/usr/bin/env bash
set -Eeuo pipefail
export LANG=ru_RU.UTF-8
export LC_ALL=ru_RU.UTF-8

# ============================================================
# VPN SERVICE DEV MENU + REPORTING (ENGLISH ONLY)
# ============================================================
# ---------- Config (override via env) ----------
export API_URL="${API_URL:-http://localhost:5272}"
export IFACE="${IFACE:-wg1}"
export ADMIN_USER="${ADMIN_USER:-admin}"
export ADMIN_PASS="${ADMIN_PASS:-admin123}"
export REPORT_KEEP="${REPORT_KEEP:-10}"
if [[ -z "${API_PORT:-}" ]]; then
  API_PORT="$(printf '%s' "$API_URL" | sed -n 's#.*://[^:/]*:\([0-9][0-9]*\).*#\1#p')"
fi
export API_PORT="${API_PORT:-5272}"

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root (one level above scripts/)
export REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Project root = repo root
export PROJ="$REPO_ROOT"

# Reports inside repo
export REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"

# ---------- Postgres (DB) defaults (override via env) ----------
export DB_MODE="${DB_MODE:-system}" # system|docker|auto
export PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT_DEFAULTED=0
if [[ -z "${PG_PORT:-}" ]]; then
  PG_PORT_DEFAULTED=1
  case "$DB_MODE" in
    system) PG_PORT=5432 ;;
    docker) PG_PORT=5433 ;;
    auto) PG_PORT=5432 ;;
    *) PG_PORT=5432 ;;
  esac
fi
export PG_PORT
export PG_DB="${PG_DB:-vpnservice}"
export PG_USER="${PG_USER:-vpnservice}"
export PG_PASSWORD="${PG_PASSWORD:-vpnservice_pwd}"
export PG_ADMIN_USER="${PG_ADMIN_USER:-postgres}"
export PG_VOLUME="${PG_VOLUME:-vpnservice_pgdata}"
export PG_COMPOSE_FILE="${PG_COMPOSE_FILE:-$REPO_ROOT/infra/postgres/docker-compose.yml}"
export PG_ENV_FILE="${PG_ENV_FILE:-$REPO_ROOT/infra/postgres/.env}"
export PG_CONTAINER="${PG_CONTAINER:-vpnservice-postgres}"

# State files
PID_FILE="$REPORT_DIR/api.pid"
LAST_TOKEN_FILE="$REPORT_DIR/last_token.txt"

# Optional behavior
# If REPORT_GIT_COMMIT=1 -> auto-commit report file to current repo
export REPORT_GIT_COMMIT="${REPORT_GIT_COMMIT:-0}"
# If SKIP_PROMPTS=1 -> suppress pause prompts (for automation)
export SKIP_PROMPTS="${SKIP_PROMPTS:-0}"

# Colors (ASCII-only output still OK)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

# ---------- Helpers ----------
die() { echo "${RED}ERROR:${NC} $*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' not found. Install it first."
}

pause() {
  [[ "$SKIP_PROMPTS" == "1" ]] && return
  read -r -p "Press Enter to continue... " _ </dev/tty || true
}

now_utc() { date -u +'%Y-%m-%d_%H-%M-%S'; }

report_name() {
  echo "$REPORT_DIR/report_$(date +'%Y-%m-%d_%H-%M-%S').log"
}

header() {
  echo
  echo "${YELLOW}>>> $*${NC}"
}

log_block() {
  local task="$1" log="$2"
  {
    echo "-------------------------------------------"
    echo "TASK: $task"
    echo "TIME_UTC: $(date -u)"
    echo "HOST: $(hostname)"
    echo "REPO_ROOT: $REPO_ROOT"
    echo "-------------------------------------------"
  } | tee -a "$log" >/dev/null
}

run_and_log() {
  # Usage: run_and_log "Task name" "$log" cmd arg1 arg2...
  local task="$1" log="$2"
  shift 2

  log_block "$task" "$log"
  {
    echo "+ $*"
    "$@"
  } 2>&1 | tee -a "$log"
  echo | tee -a "$log" >/dev/null
}

run_shell_and_log() {
  # For commands that require shell parsing / pipes
  # Usage: run_shell_and_log "Task" "$log" "shell command..."
  local task="$1" log="$2" cmd="$3"
  log_block "$task" "$log"
  {
    echo "+ bash -lc $cmd"
    bash -lc "$cmd"
  } 2>&1 | tee -a "$log"
  echo | tee -a "$log" >/dev/null
}

# ---------- Git helpers ----------
git_repo_root() {
  git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1
}

git_commit_report_if_enabled() {
  local report="$1"
  [[ "$REPORT_GIT_COMMIT" == "1" ]] || return 0
  git_repo_root || return 0

  # Only commit if file exists and repo is cleanable
  if [[ -f "$report" ]]; then
    git -C "$REPO_ROOT" add "$report" >/dev/null 2>&1 || true
    # Commit only if staged changes exist
    if ! git -C "$REPO_ROOT" diff --cached --quiet; then
      git -C "$REPO_ROOT" commit -m "Add report $(basename "$report")" >/dev/null 2>&1 || true
    fi
  fi
}

auto_commit_report() {
  local report="$1" context_tag="$2"
  local report_rel branch

  git_repo_root || {
    echo "Auto-commit skipped: not a git repo. Report: $report"
    return 1
  }

  if [[ -z "$report" || ! -f "$report" ]]; then
    echo "Auto-commit skipped: report not found."
    return 1
  fi

  if [[ "$report" == *"/infra/postgres/.env" || "$report" == *"infra/postgres/.env" ]]; then
    echo "Auto-commit skipped: refusing to commit .env."
    return 1
  fi

  if [[ "$report" == "$REPO_ROOT"* ]]; then
    report_rel="${report#"$REPO_ROOT"/}"
  else
    echo "Auto-commit skipped: report not inside repo. Report: $report"
    return 1
  fi

  git -C "$REPO_ROOT" add -f -- "$report_rel" >/dev/null 2>&1 || true

  if git -C "$REPO_ROOT" diff --cached --quiet -- "$report_rel"; then
    echo "Auto-commit skipped: nothing staged for $report_rel"
    return 0
  fi

  git -C "$REPO_ROOT" commit -m "report: $context_tag $(basename "$report")" --only -- "$report_rel" >/dev/null 2>&1 || true

  branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    echo "Auto-commit done: $report_rel (no branch detected)."
    return 0
  fi

  if ! git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
    echo "Auto-commit done locally (no remote). Report: $report_rel"
    return 0
  fi

  if git -C "$REPO_ROOT" push origin "$branch" >/dev/null 2>&1; then
    echo "Auto-commit pushed: $report_rel"
    return 0
  fi

  if git -C "$REPO_ROOT" pull --rebase origin "$branch" >/dev/null 2>&1 && \
     git -C "$REPO_ROOT" push origin "$branch" >/dev/null 2>&1; then
    echo "Auto-commit pushed after rebase: $report_rel"
    return 0
  fi

  echo "Auto-commit push failed. Report: $report_rel"
  return 1
}

cleanup_reports_keep_last() {
  local keep="${1:-$REPORT_KEEP}"

  # Safety
  [[ "$keep" =~ ^[0-9]+$ ]] || { echo "Cleanup: keep must be a number"; return 1; }
  (( keep >= 1 )) || { echo "Cleanup: keep must be >= 1"; return 1; }

  cd "$REPO_ROOT" || return 1

  # Abort if working tree is dirty
  if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
    echo "Cleanup aborted: working tree is dirty. Commit or stash changes first." >&2
    return 1
  fi

  # Collect reports sorted by mtime desc, delete everything after first N
  mapfile -t reports < <(ls -1t reports/report_*.log 2>/dev/null || true)

  if [[ "${#reports[@]}" -le "$keep" ]]; then
    echo "Cleanup: nothing to delete (reports=${#reports[@]}, keep=$keep)."
    return 0
  fi

  local to_delete=("${reports[@]:$keep}")

  echo "Cleanup: keeping last $keep reports, deleting ${#to_delete[@]} old reports:"
  printf ' - %s\n' "${to_delete[@]}"

  rm -f "${to_delete[@]}"

  # Stage deletions
  git add -A reports/ >/dev/null 2>&1 || true

  # Commit only if something staged
  if ! git diff --cached --quiet; then
    git commit -m "Cleanup reports: keep last $keep" >/dev/null 2>&1 || true
    echo "Cleanup: committed."
  else
    echo "Cleanup: no staged changes."
  fi
}

# ---------- API process helpers ----------
api_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

api_start_bg() {
  local log="$1"
  need dotnet
  need curl

  if api_running; then
    echo "${YELLOW}API already running. PID=$(cat "$PID_FILE")${NC}" | tee -a "$log" >/dev/null
    return 0
  fi

  # Start in background with nohup; log to a stable file
  local api_out="${log}.api.out"

  log_block "API: start background" "$log"
  (
    cd "$PROJ"
    # If port is already in use, do not start a second instance
    if port_in_use "$API_PORT"; then
      echo "${YELLOW}API port $API_PORT already in use. Not starting a second instance.${NC}" | tee -a "$log" >/dev/null
      if command -v ss >/dev/null 2>&1; then
        ss -ltnp | grep ":$API_PORT" | tee -a "$log" >/dev/null || true
      elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"$API_PORT" -sTCP:LISTEN | tee -a "$log" >/dev/null || true
      elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn | grep ":$API_PORT" | tee -a "$log" >/dev/null || true
      fi
      return 0
    fi

    nohup dotnet run --project VpnService.Api >"$api_out" 2>&1 &
    echo $! >"$PID_FILE"
  )

  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  echo "Started API background PID=$pid" | tee -a "$log" >/dev/null
  echo "API stdout/stderr: $api_out" | tee -a "$log" >/dev/null

  # Health probe (retry up to 60s)
  log_block "API: health probe" "$log"
  local ok=0
  for i in {1..60}; do
    echo "Waiting for health... ($i/60)" | tee -a "$log" >/dev/null
    if curl -fsS "$API_URL/health" >/dev/null 2>&1; then ok=1; break; fi
    sleep 1
  done

  if [[ "$ok" == "1" ]]; then
    echo "Health: OK ($API_URL/health)" | tee -a "$log" >/dev/null
  else
    echo "${RED}Health: FAILED${NC} ($API_URL/health)" | tee -a "$log" >/dev/null
    echo "Check: $api_out" | tee -a "$log" >/dev/null
    return 1
  fi
}

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep -q ":$port"
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -q ":$port"
    return $?
  fi
  return 1
}

api_stop_bg() {
  local log="$1"

  if ! api_running; then
    echo "${YELLOW}API is not running.${NC}" | tee -a "$log" >/dev/null
    rm -f "$PID_FILE" >/dev/null 2>&1 || true
    return 0
  fi

  local pid
  pid="$(cat "$PID_FILE")"

  run_and_log "API: stop (PID=$pid)" "$log" bash -lc "kill $pid >/dev/null 2>&1 || true"
  sleep 1

  if kill -0 "$pid" >/dev/null 2>&1; then
    run_and_log "API: force kill (PID=$pid)" "$log" bash -lc "kill -9 $pid >/dev/null 2>&1 || true"
  fi

  rm -f "$PID_FILE" >/dev/null 2>&1 || true
  echo "Stopped." | tee -a "$log" >/dev/null
}

api_run_fg() {
  need dotnet
  cd "$PROJ"
  dotnet run --project VpnService.Api
}

# ---------- Auth/token ----------
get_token() {
  need curl
  need jq

  local resp token
  resp="$(curl -sS -X POST "$API_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" || true)"
  printf '%s' "$resp" > "$REPORT_DIR/last_login_response.json"
  LAST_LOGIN_RESP="$resp"

  if [[ -z "${resp:-}" ]]; then
    echo "${RED}ERROR:${NC} login response is empty." >&2
    return 1
  fi

  token="$(jq -r '.accessToken // empty' "$REPORT_DIR/last_login_response.json" 2>/dev/null || true)"
  if [[ -z "${token:-}" ]]; then
    return 1
  fi

  printf '%s' "$token"
}

auth_and_save_token() {
  local log="$1"
  need curl
  need jq

  run_and_log "Auth: health check" "$log" curl -fsS "$API_URL/health"

  log_block "Auth: login (get token)" "$log"
  local token
  if ! token="$(get_token)"; then
    token=""
  fi

  if [[ -z "${token:-}" ]]; then
    echo "${RED}ERROR:${NC} token is empty. Check credentials or /api/v1/auth/login." | tee -a "$log" >/dev/null
    echo "Login response (first 300 chars): $(printf '%s' "$LAST_LOGIN_RESP" | head -c 300)" | tee -a "$log" >/dev/null
    return 1
  fi

  echo "$token" > "$LAST_TOKEN_FILE"
  echo "Token saved: $LAST_TOKEN_FILE" | tee -a "$log" >/dev/null
  echo "Token preview: ${token:0:25}..." | tee -a "$log" >/dev/null
  echo "Auth OK. Token saved." | tee -a "$log" >/dev/null
}

probe_wg_endpoints() {
  local log="$1"
  need curl

  if [[ ! -s "$LAST_TOKEN_FILE" ]]; then
    echo "${YELLOW}No token file. Run Auth first.${NC}" | tee -a "$log" >/dev/null
    return 1
  fi

  local token
  token="$(cat "$LAST_TOKEN_FILE")"

  log_block "Probe: WG endpoints" "$log"

  local urls=(
    "$API_URL/api/v1/admin/wg/state?iface=$IFACE"
    "$API_URL/api/v1/admin/wg/state"
    "$API_URL/api/v1/wg/state?iface=$IFACE"
    "$API_URL/admin/wg/state?iface=$IFACE"
    "$API_URL/api/v1/admin/wg/reconcile?iface=$IFACE&mode=dry-run"
  )

  local u code ok=0
  for u in "${urls[@]}"; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" "$u" -H "Authorization: Bearer $token" || true)"
    echo "GET $u -> HTTP $code" | tee -a "$log" >/dev/null
    [[ "$code" == "200" ]] && ok=1
  done

  if [[ "$ok" == "0" ]]; then
    echo "${YELLOW}No WG endpoint returned 200 yet. This is OK if not implemented in Stage 3.2 yet.${NC}" | tee -a "$log" >/dev/null
  fi
}

stage32_dry_run() {
  local log="$1"
  need curl

  if [[ ! -s "$LAST_TOKEN_FILE" ]]; then
    echo "${YELLOW}No token file. Running Auth step first...${NC}" | tee -a "$log" >/dev/null
    auth_and_save_token "$log" || return 1
  fi

  local token
  token="$(cat "$LAST_TOKEN_FILE")"

  # Try a likely reconcile endpoint first
  local url="$API_URL/api/v1/admin/wg/reconcile?iface=$IFACE&mode=dry-run"

  log_block "Stage 3.2: call reconcile dry-run" "$log"
  echo "GET $url" | tee -a "$log" >/dev/null

  local code
  code="$(curl -sS -o "$REPORT_DIR/last_reconcile.json" -w "%{http_code}" \
    "$url" -H "Authorization: Bearer $token" || true)"

  echo "HTTP $code, saved: $REPORT_DIR/last_reconcile.json" | tee -a "$log" >/dev/null

  if [[ "$code" != "200" ]]; then
    echo "${YELLOW}Dry-run endpoint not available yet (HTTP $code). Implement it in API to complete Stage 3.2.${NC}" | tee -a "$log" >/dev/null
    return 1
  fi

  # Show short preview
  run_shell_and_log "Stage 3.2: reconcile preview (head)" "$log" "head -n 80 '$REPORT_DIR/last_reconcile.json'"
}

# ---------- Stage shortcuts ----------
stage32_check() {
  local log="$1"
  api_start_bg "$log" || return 1
  auth_and_save_token "$log" || return 1
  stage32_dry_run "$log"
}

stage33_call() {
  local log="$1"
  need curl

  if [[ ! -s "$LAST_TOKEN_FILE" ]]; then
    echo "${YELLOW}No token file. Run Auth first.${NC}" | tee -a "$log" >/dev/null
    return 1
  fi

  local token url code
  token="$(cat "$LAST_TOKEN_FILE")"
  url="$API_URL/api/v1/admin/wg/state?iface=$IFACE"

  log_block "Stage 3.3: call wg state" "$log"
  echo "GET $url" | tee -a "$log" >/dev/null

  code="$(curl -sS -o "$REPORT_DIR/last_wg_state.json" -w "%{http_code}" \
    "$url" -H "Authorization: Bearer $token" || true)"

  echo "HTTP $code, saved: $REPORT_DIR/last_wg_state.json" | tee -a "$log" >/dev/null

  if [[ "$code" != "200" ]]; then
    echo "${YELLOW}WG state endpoint not available yet (HTTP $code).${NC}" | tee -a "$log" >/dev/null
    return 1
  fi

  run_shell_and_log "Stage 3.3: wg state preview (first 400 chars)" "$log" \
    "head -c 400 '$REPORT_DIR/last_wg_state.json'"
}

stage33_check() {
  local log="$1"
  api_start_bg "$log" || return 1
  auth_and_save_token "$log" || return 1
  stage33_call "$log"
}

stage3233_check_all() {
  local log="$1"
  api_start_bg "$log" || return 1
  auth_and_save_token "$log" || return 1
  stage32_dry_run "$log" || return 1
  stage33_call "$log"
}

# ---------- Postgres (Docker) ----------
# Default host port is 5433 to avoid collisions. Set PG_PORT=5432 in infra/postgres/.env if desired.
docker_ready() {
  local log="${1:-}"
  need docker
  if ! docker compose version >/dev/null 2>&1; then
    if [[ -n "$log" ]]; then
      echo "${RED}ERROR:${NC} docker compose is not available." | tee -a "$log" >/dev/null
    else
      echo "${RED}ERROR:${NC} docker compose is not available." >&2
    fi
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    if [[ -n "$log" ]]; then
      echo "${RED}ERROR:${NC} docker daemon is not running." | tee -a "$log" >/dev/null
    else
      echo "${RED}ERROR:${NC} docker daemon is not running." >&2
    fi
    return 1
  fi
}

pg_require_files() {
  local log="${1:-}"
  if [[ ! -f "$PG_COMPOSE_FILE" ]]; then
    if [[ -n "$log" ]]; then
      echo "${RED}ERROR:${NC} Missing $PG_COMPOSE_FILE" | tee -a "$log" >/dev/null
    else
      echo "${RED}ERROR:${NC} Missing $PG_COMPOSE_FILE" >&2
    fi
    return 1
  fi
  if [[ ! -f "$PG_ENV_FILE" ]]; then
    if [[ -n "$log" ]]; then
      echo "${RED}ERROR:${NC} Missing $PG_ENV_FILE" | tee -a "$log" >/dev/null
    else
      echo "${RED}ERROR:${NC} Missing $PG_ENV_FILE" >&2
    fi
    return 1
  fi
}

pg_diag() {
  local log="$1"
  docker_ready "$log" || return 1
  pg_require_files "$log" || return 1

  run_shell_and_log "Postgres: ports 5432/5433 in use" "$log" \
    "ss -lntp 2>/dev/null | { grep ':5432' || true; grep ':5433' || true; } || true"

  run_and_log "Postgres: docker ps -a (filtered)" "$log" \
    docker ps -a --filter "name=$PG_CONTAINER" --filter "name=postgres"

  run_and_log "Postgres: docker compose config --services" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" config --services

  run_and_log "Postgres: docker compose ps" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" ps

  run_shell_and_log "Postgres: docker inspect state/health" "$log" \
    "docker inspect --format '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' '$PG_CONTAINER' 2>/dev/null || true"

  run_shell_and_log "Postgres: docker logs (tail 120)" "$log" \
    "if docker ps -a --format '{{.Names}}' | grep -qx '$PG_CONTAINER'; then docker logs --tail 120 '$PG_CONTAINER'; else echo 'Container not found'; fi"
}

pg_wait_healthy() {
  local log="$1" ok=0
  local state health
  for i in {1..60}; do
    state="$(docker inspect --format='{{.State.Status}}' "$PG_CONTAINER" 2>/dev/null || true)"
    health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$PG_CONTAINER" 2>/dev/null || true)"
    echo "Waiting for Postgres health... ($i/60) state=${state:-unknown} health=${health:-unknown}" | tee -a "$log" >/dev/null
    [[ "$health" == "healthy" ]] && ok=1 && break
    sleep 1
  done
  [[ "$ok" == "1" ]]
}

pg_up() {
  local log="$1"
  docker_ready "$log" || return 1
  pg_require_files "$log" || return 1

  run_and_log "Postgres: docker compose up" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" up -d --remove-orphans

  if pg_wait_healthy "$log"; then
    echo "Postgres is healthy." | tee -a "$log" >/dev/null
    return 0
  fi

  echo "${YELLOW}Postgres did not become healthy. Running diagnostics...${NC}" | tee -a "$log" >/dev/null
  pg_diag "$log" || true

  run_and_log "Postgres: docker compose down (remediate)" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" down
  run_and_log "Postgres: docker compose up (remediate)" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" up -d --remove-orphans

  if pg_wait_healthy "$log"; then
    echo "Postgres is healthy after remediation." | tee -a "$log" >/dev/null
    return 0
  fi

  local state
  state="$(docker inspect --format='{{.State.Status}}' "$PG_CONTAINER" 2>/dev/null || true)"
  if [[ "$state" == "created" ]]; then
    run_and_log "Postgres: docker start (remediate created)" "$log" docker start "$PG_CONTAINER" || true
    if pg_wait_healthy "$log"; then
      echo "Postgres is healthy after docker start." | tee -a "$log" >/dev/null
      return 0
    fi
  fi

  echo "${RED}Postgres failed to become healthy. See report: $log${NC}" | tee -a "$log" >/dev/null
  return 1
}

pg_status() {
  local log="$1"
  docker_ready "$log" || return 1
  pg_require_files "$log" || return 1

  run_and_log "Postgres: docker compose ps" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" ps
  run_shell_and_log "Postgres: container status" "$log" \
    "docker inspect --format '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' '$PG_CONTAINER' 2>/dev/null || true"
  local state health
  state="$(docker inspect --format='{{.State.Status}}' "$PG_CONTAINER" 2>/dev/null || true)"
  health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$PG_CONTAINER" 2>/dev/null || true)"
  if [[ "$state" != "running" || "$health" != "healthy" ]]; then
    echo "Hint: Run P1 or see P3 logs / diagnostics." | tee -a "$log" >/dev/null
  fi
}

pg_logs() {
  local log="$1"
  docker_ready "$log" || return 1
  run_and_log "Postgres: docker logs (tail 120)" "$log" docker logs --tail 120 "$PG_CONTAINER"
}

pg_psql() {
  local log="$1"
  docker_ready "$log" || return 1

  log_block "Postgres: psql (interactive)" "$log"
  echo "+ docker exec -it $PG_CONTAINER psql -U $PG_USER -d $PG_DB" | tee -a "$log" >/dev/null
  docker exec -it "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB"
  echo | tee -a "$log" >/dev/null
}

# ---------- Postgres helpers ----------
pg_mask_secret() {
  local s="${1:-}"
  if [[ -z "$s" ]]; then
    echo "(empty)"
    return
  fi
  if [[ "${#s}" -le 2 ]]; then
    echo "${s:0:1}***"
    return
  fi
  echo "${s:0:2}***"
}

pg_conn_info() {
  local mode="$1" port="$2"
  echo "DB_MODE=$mode"
  echo "PG_HOST=$PG_HOST"
  echo "PG_PORT=$port"
  echo "PG_DB=$PG_DB"
  echo "PG_USER=$PG_USER"
  echo "PG_PASSWORD=$(pg_mask_secret "$PG_PASSWORD")"
  echo "PG_ADMIN_USER=$PG_ADMIN_USER"
}

pg_is_listening() {
  local port="$1"
  if ! command -v ss >/dev/null 2>&1; then
    return 1
  fi
  ss -lntp 2>/dev/null | grep -q ":$port"
}

db_docker_running() {
  command -v docker >/dev/null 2>&1 || return 1
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$PG_CONTAINER"
}

db_detect_mode() {
  case "$DB_MODE" in
    system|docker)
      echo "$DB_MODE"
      ;;
    auto)
      if db_docker_running; then
        echo "docker"
        return
      fi
      if pg_is_listening 5432; then
        echo "system"
        return
      fi
      echo "docker"
      ;;
    *)
      echo "system"
      ;;
  esac
}

db_select_mode() {
  local mode
  mode="$(db_detect_mode)"
  if [[ "$PG_PORT_DEFAULTED" == "1" ]]; then
    if [[ "$mode" == "docker" ]]; then
      PG_PORT=5433
    else
      PG_PORT=5432
    fi
  fi
  echo "$mode"
}

db_log_error() {
  local log="$1" msg="$2"
  {
    echo
    echo "ERROR"
    echo "$msg"
    echo
  } | tee -a "$log" >/dev/null
}

pg_down() {
  local log="$1"
  docker_ready "$log" || return 1
  pg_require_files "$log" || return 1
  run_and_log "Postgres: docker compose down" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" down
}

pg_print_conn() {
  local log="$1"
  log_block "Postgres: connection string" "$log"
  echo "ConnectionStrings__Default=Host=$PG_HOST;Port=$PG_PORT;Database=$PG_DB;Username=$PG_USER;Password=$(pg_mask_secret "$PG_PASSWORD")" \
    | tee -a "$log" >/dev/null
}

# ---------- Postgres (DB menu) ----------
db_run_action() {
  local log="$1" tag="$2"
  shift 2
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi
  if [[ "$rc" -eq 2 ]]; then
    return 0
  fi
  db_log_error "$log" "DB action failed: $tag"
  auto_commit_report "$log" "$tag" || true
  return "$rc"
}

db_status() {
  local log="$1"
  local mode
  mode="$(db_select_mode)"

  log_block "DB: status" "$log"
  {
    pg_conn_info "$mode" "$PG_PORT"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    run_shell_and_log "DB: systemctl status postgresql" "$log" \
      "systemctl is-active postgresql || systemctl status postgresql"
    run_shell_and_log "DB: listener on $PG_PORT" "$log" \
      "ss -lntp 2>/dev/null | grep ':$PG_PORT'"
    run_shell_and_log "DB: pg_isready" "$log" \
      "pg_isready -h '$PG_HOST' -p '$PG_PORT'"
    return 0
  fi

  docker_ready "$log" || return 1
  pg_require_files "$log" || return 1
  run_and_log "DB: docker compose ps" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" ps
  run_shell_and_log "DB: docker container health" "$log" \
    "docker inspect --format '{{.State.Status}}{{if .State.Health}}/{{.State.Health.Status}}{{end}}' '$PG_CONTAINER' 2>/dev/null || true"
  run_shell_and_log "DB: pg_isready (container)" "$log" \
    "docker exec -i '$PG_CONTAINER' pg_isready -U '$PG_USER' -d '$PG_DB'"
}

db_diag() {
  local log="$1"
  local mode
  mode="$(db_select_mode)"

  run_shell_and_log "DB: ports 5432/5433" "$log" \
    "ss -lntp 2>/dev/null | { grep ':5432' || true; grep ':5433' || true; } || true"

  if command -v docker >/dev/null 2>&1; then
    run_and_log "DB: docker ps -a (filtered)" "$log" \
      docker ps -a --filter "name=$PG_CONTAINER" --filter "name=postgres"
  else
    log_block "DB: docker ps -a (filtered)" "$log"
    echo "docker not installed." | tee -a "$log" >/dev/null
  fi

  if [[ "$mode" == "system" ]]; then
    run_shell_and_log "DB: systemctl status postgresql" "$log" \
      "systemctl status postgresql || true"
    return 0
  fi

  docker_ready "$log" || return 1
  pg_require_files "$log" || return 1
  run_and_log "DB: docker compose config --services" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" config --services
  run_and_log "DB: docker compose ps" "$log" \
    docker compose --env-file "$PG_ENV_FILE" -f "$PG_COMPOSE_FILE" ps
}

db_psql_shell() {
  local log="$1"
  local mode
  mode="$(db_select_mode)"

  log_block "DB: psql shell (interactive)" "$log"
  {
    pg_conn_info "$mode" "$PG_PORT"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    echo "+ sudo -u $PG_ADMIN_USER psql -h $PG_HOST -p $PG_PORT -U $PG_ADMIN_USER -d $PG_DB" \
      | tee -a "$log" >/dev/null
    sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" -d "$PG_DB"
  else
    docker_ready "$log" || return 1
    echo "+ docker exec -it $PG_CONTAINER psql -U $PG_USER -d $PG_DB" \
      | tee -a "$log" >/dev/null
    docker exec -e PGPASSWORD="$PG_PASSWORD" -it "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB"
  fi
  echo | tee -a "$log" >/dev/null
}

db_list_dbs() {
  local log="$1"
  local mode
  mode="$(db_select_mode)"

  log_block "DB: list databases" "$log"
  {
    pg_conn_info "$mode" "$PG_PORT"
    echo "+ psql (admin) list databases"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -Atc "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;"
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -Atc "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;"
    } 2>&1 | tee -a "$log"
  fi
}

db_create_db() {
  local log="$1"
  local db
  read -r -p "Database name [$PG_DB]: " db </dev/tty || true
  db="${db:-$PG_DB}"

  local mode
  mode="$(db_select_mode)"

  log_block "DB: create database" "$log"
  {
    echo "Target DB: $db"
    echo "Owner: $PG_USER"
    echo "+ psql (admin) create database if missing"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -v owner="$PG_USER" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'db', :'owner');
  END IF;
END $$;
SQL
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -v owner="$PG_USER" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'db', :'owner');
  END IF;
END $$;
SQL
    } 2>&1 | tee -a "$log"
  fi
}

db_drop_db() {
  local log="$1"
  local db confirm
  read -r -p "Database to drop [$PG_DB]: " db </dev/tty || true
  db="${db:-$PG_DB}"
  read -r -p "Type '$db' to confirm drop: " confirm </dev/tty || true
  if [[ "$confirm" != "$db" ]]; then
    log_block "DB: drop database" "$log"
    echo "Canceled: confirmation mismatch." | tee -a "$log" >/dev/null
    return 2
  fi

  local mode
  mode="$(db_select_mode)"

  log_block "DB: drop database" "$log"
  echo "Target DB: $db" | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db' AND pid <> pg_backend_pid();"
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -c \
        "DROP DATABASE IF EXISTS :\"db\";"
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db' AND pid <> pg_backend_pid();"
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -c \
        "DROP DATABASE IF EXISTS :\"db\";"
    } 2>&1 | tee -a "$log"
  fi
}

db_ensure_bootstrap() {
  local log="$1"
  local mode
  mode="$(db_select_mode)"
  local admin_user
  admin_user="$PG_USER"

  log_block "DB: ensure role + database" "$log"
  {
    pg_conn_info "$mode" "$PG_PORT"
    echo "Bootstrap user: $admin_user"
    echo "Role: $PG_USER"
    echo "Database: $PG_DB"
    echo "+ psql (admin) ensure role/db (password redacted)"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$admin_user" \
        -v ON_ERROR_STOP=1 -v role="$PG_USER" -v pwd="$PG_PASSWORD" -v db="$PG_DB" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pwd');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', :'role', :'pwd');
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'db', :'role');
  END IF;
END $$;
SQL
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$admin_user" \
        -v ON_ERROR_STOP=1 -v role="$PG_USER" -v pwd="$PG_PASSWORD" -v db="$PG_DB" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'pwd');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', :'role', :'pwd');
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') THEN
    EXECUTE format('CREATE DATABASE %I OWNER %I', :'db', :'role');
  END IF;
END $$;
SQL
    } 2>&1 | tee -a "$log"
  fi
}

db_list_tables() {
  local log="$1"
  local db
  read -r -p "Database name [$PG_DB]: " db </dev/tty || true
  db="${db:-$PG_DB}"

  local mode
  mode="$(db_select_mode)"

  log_block "DB: list tables" "$log"
  {
    echo "Target DB: $db"
    echo "+ psql (admin) list tables"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" -d "$db" \
        -v ON_ERROR_STOP=1 -Atc \
        "SELECT schemaname || '.' || tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1;"
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" -d "$db" \
        -v ON_ERROR_STOP=1 -Atc \
        "SELECT schemaname || '.' || tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') ORDER BY 1;"
    } 2>&1 | tee -a "$log"
  fi
}

db_backup() {
  local log="$1"
  local db
  read -r -p "Database to backup [$PG_DB]: " db </dev/tty || true
  db="${db:-$PG_DB}"

  local mode
  mode="$(db_select_mode)"
  local backup="$REPORT_DIR/db_backup_${db}_$(date +'%Y-%m-%d_%H-%M-%S').sql"

  log_block "DB: backup (pg_dump)" "$log"
  if [[ "$mode" == "docker" ]]; then
    docker_ready "$log" || return 1
  fi
  {
    echo "Target DB: $db"
    echo "Backup file: $backup"
    echo "+ pg_dump (mode=$mode) > $backup"
    if [[ "$mode" == "system" ]]; then
      sudo -u "$PG_ADMIN_USER" pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" "$db" >"$backup"
    else
      docker exec -e PGPASSWORD="$PG_PASSWORD" "$PG_CONTAINER" pg_dump -U "$PG_USER" "$db" >"$backup"
    fi
    echo "Backup complete: $backup"
  } 2>&1 | tee -a "$log"
}

db_restore() {
  local log="$1"
  local db file confirm
  read -r -p "Database to restore into [$PG_DB]: " db </dev/tty || true
  db="${db:-$PG_DB}"
  read -r -p "Path to backup file: " file </dev/tty || true
  if [[ -z "$file" || ! -f "$file" ]]; then
    log_block "DB: restore" "$log"
    echo "Missing backup file: $file" | tee -a "$log" >/dev/null
    return 1
  fi
  read -r -p "Type '$db' to confirm restore: " confirm </dev/tty || true
  if [[ "$confirm" != "$db" ]]; then
    log_block "DB: restore" "$log"
    echo "Canceled: confirmation mismatch." | tee -a "$log" >/dev/null
    return 2
  fi

  local mode
  mode="$(db_select_mode)"

  log_block "DB: restore (psql)" "$log"
  if [[ "$mode" == "docker" ]]; then
    docker_ready "$log" || return 1
  fi
  {
    echo "Target DB: $db"
    echo "Backup file: $file"
    echo "+ psql (mode=$mode) < $file"
    if [[ "$mode" == "system" ]]; then
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" -d "$db" -f "$file"
    else
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" -d "$db" <"$file"
    fi
  } 2>&1 | tee -a "$log"
}

db_show_connections() {
  local log="$1"
  local mode
  mode="$(db_select_mode)"

  log_block "DB: active connections" "$log"
  {
    pg_conn_info "$mode" "$PG_PORT"
    echo "+ psql (admin) show pg_stat_activity"
  } | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -Atc \
        "SELECT pid, usename, datname, client_addr, state, query_start FROM pg_stat_activity ORDER BY query_start DESC;"
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -Atc \
        "SELECT pid, usename, datname, client_addr, state, query_start FROM pg_stat_activity ORDER BY query_start DESC;"
    } 2>&1 | tee -a "$log"
  fi
}

db_kill_connections() {
  local log="$1"
  local db confirm
  read -r -p "Database to kill connections [$PG_DB]: " db </dev/tty || true
  db="${db:-$PG_DB}"
  read -r -p "Type '$db' to confirm kill: " confirm </dev/tty || true
  if [[ "$confirm" != "$db" ]]; then
    log_block "DB: kill connections" "$log"
    echo "Canceled: confirmation mismatch." | tee -a "$log" >/dev/null
    return 2
  fi

  local mode
  mode="$(db_select_mode)"

  log_block "DB: kill connections" "$log"
  echo "Target DB: $db" | tee -a "$log" >/dev/null

  if [[ "$mode" == "system" ]]; then
    {
      sudo -u "$PG_ADMIN_USER" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db' AND pid <> pg_backend_pid();"
    } 2>&1 | tee -a "$log"
  else
    docker_ready "$log" || return 1
    {
      docker exec -e PGPASSWORD="$PG_PASSWORD" -i "$PG_CONTAINER" psql -U "$PG_ADMIN_USER" \
        -v ON_ERROR_STOP=1 -v db="$db" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'db' AND pid <> pg_backend_pid();"
    } 2>&1 | tee -a "$log"
  fi
}

# ---------- Diagnostics ----------
system_diag() {
  local log="$1"
  need ip
  need ping

  run_and_log "System: whoami/hostname/date" "$log" whoami
  run_and_log "System: hostname" "$log" hostname
  run_and_log "System: date (UTC)" "$log" date -u

  if command -v timedatectl >/dev/null 2>&1; then
    run_shell_and_log "System: timedatectl (top)" "$log" "timedatectl | sed -n '1,10p'"
  fi

  run_and_log "Network: ip -br a" "$log" ip -br a
  run_and_log "Network: routes" "$log" ip r
  run_and_log "Network: ping 8.8.8.8" "$log" ping -c 1 8.8.8.8
}

wg_diag() {
  local log="$1"
  need wg

  # wg show does not require sudo if already root; keep it clean
  run_and_log "WireGuard: wg show" "$log" wg show
  run_shell_and_log "WireGuard: wg show dump (masked, first 30 lines)" "$log" \
    "wg show '$IFACE' dump | awk 'NR==1{\$1=\"(hidden)\"}1' | head -n 30"
}

git_update() {
  local log="$1"
  need git

  run_shell_and_log "Git: status" "$log" "cd '$PROJ' && git status"
  run_shell_and_log "Git: fetch --all --prune" "$log" "cd '$PROJ' && git fetch --all --prune"
  run_shell_and_log "Git: pull --rebase" "$log" "cd '$PROJ' && git pull --rebase"
  run_shell_and_log "Git: log -5" "$log" "cd '$PROJ' && git log -5 --oneline"
}

build_check() {
  local log="$1"
  need dotnet
  need find

  run_shell_and_log "Build: dotnet --info (top)" "$log" "dotnet --info | sed -n '1,25p'"
  run_shell_and_log "Build: clean" "$log" "cd '$PROJ' && dotnet clean"
  run_shell_and_log "Build: remove bin/obj" "$log" "cd '$PROJ' && find . -type d \\( -name bin -o -name obj \\) -prune -exec rm -rf {} +"
  run_shell_and_log "Build: restore" "$log" "cd '$PROJ' && dotnet restore"
  run_shell_and_log "Build: build Debug" "$log" "cd '$PROJ' && dotnet build -c Debug"
}

route_audit() {
  local log="$1"
  need grep

  run_shell_and_log "Route audit: WireGuard controllers/classes" "$log" \
    "cd '$PROJ' && grep -R --line-number 'class .*WireGuard' VpnService.Api/Controllers || true"

  run_shell_and_log "Route audit: wg routes" "$log" \
    "cd '$PROJ' && { grep -R --line-number 'admin/wg/state' VpnService.Api/Controllers || true; \
                     grep -R --line-number '\\[Route' VpnService.Api/Controllers | grep -i wg || true; }"
}

smoke_auth_and_state() {
  local log="$1"
  need curl
  need python3

  run_and_log "Smoke: health" "$log" curl -sS "$API_URL/health"

  log_block "Smoke: login and token" "$log"
  local token
  token="$(get_token)"

  if [[ -z "${token:-}" ]]; then
    echo "${RED}ERROR:${NC} access token is empty. Check /api/v1/auth/login and API logs." | tee -a "$log" >/dev/null
    echo "Login response (first 300 chars): $(printf '%s' "$LAST_LOGIN_RESP" | head -c 300)" | tee -a "$log" >/dev/null
    echo "Hint: verify LoginRequest DTO and credentials." | tee -a "$log" >/dev/null
    return 1
  fi

  echo "$token" >"$LAST_TOKEN_FILE"
  echo "TOKEN(short): ${token:0:25}..." | tee -a "$log" >/dev/null
  echo | tee -a "$log" >/dev/null

  run_shell_and_log "Smoke: WG state (protected)" "$log" \
    "curl -sS '$API_URL/api/v1/admin/wg/state?iface=$IFACE' -H 'Authorization: Bearer $token'"
}

list_reports() {
  header "Recent reports in $REPORT_DIR"
  ls -lh "$REPORT_DIR" | tail -n 30
}

# ---------- Menu ----------
show_menu() {
  clear
  cat <<EOF
==========================================
   VPN SERVICE DEV MENU + REPORTING
==========================================
Repo root : $REPO_ROOT
Project   : $PROJ
API URL   : $API_URL
WG iface  : $IFACE
Reports   : $REPORT_DIR
AutoCommit: $REPORT_GIT_COMMIT
------------------------------------------
1) [Full Audit] Run all checks and write report
2) [Diag] System diagnostics
3) [WG] WireGuard diagnostics
4) [Git] Update project (fetch/pull --rebase)
5) [Build] Clean/restore/build
6) [API] API control (fg/bg/stop)
7) [Smoke] API test (Auth + WG state)
8) [Routes] Route audit (catch AmbiguousMatch)
9) [Auth] Login and save token
------------------------------------------
[DB - Postgres (Docker)]
P1) Postgres up
P2) Postgres status
P3) Postgres logs
P4) Postgres psql
P5) Postgres down
P6) Print Postgres connection string
P7) Postgres diagnostics
------------------------------------------
[DB - Postgres]
D1) DB status/health
D2) DB diagnostics
D3) psql shell
D4) List databases
D5) Create database
D6) Drop database
D7) Ensure vpnservice DB + user
D8) List tables in a database
D9) Backup database to reports
DA) Restore database from file
DB) Show active connections
DC) Kill connections to a DB
------------------------------------------
[STAGES]
S2) Stage 3.2 check (auth + reconcile)
S3) Stage 3.3 check (auth + wg state)
SA) Stage 3.2+3.3 full check
A) [Probe] Probe WG endpoints
B) [Stage3.2] Dry-run reconcile (if endpoint exists)
C) [Reports] Cleanup reports (keep last N)
R) [Sync] Сбор отчета и отправка на Windows
L) [Logs] List recent reports
0) Exit
==========================================
EOF
}

api_menu() {
  clear
  cat <<EOF
------------------------------------------
API CONTROL  (API_URL=$API_URL)
------------------------------------------
1) Run API foreground (Ctrl+C to stop)
2) Start API in background
3) Stop background API
0) Back
------------------------------------------
EOF
  read -r -p "Select: " a </dev/tty || true
  local report
  report="$(report_name)"

  case "$a" in
    1) api_run_fg ;;
    2) api_start_bg "$report"; echo "API log: ${report}.api.out"; pause ;;
    3) api_stop_bg "$report"; pause ;;
    0) : ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
}

run_full_audit() {
  local REPORT_NAME REPORT_PATH
  REPORT_NAME="report_$(date -u +'%Y-%m-%d_%H-%M-%S').log"
  REPORT_PATH="$REPORT_DIR/$REPORT_NAME"

  header "Full audit"
  echo "Report: $REPORT_PATH"

  mkdir -p "$REPORT_DIR"

  {
    echo "=== VPN SERVICE AUDIT REPORT ==="
    echo "TIME_UTC: $(date -u)"
    echo "HOST: $(hostname)"
    echo "USER: $(whoami)"
    echo "REPO_ROOT: $REPO_ROOT"
    echo "API_URL: $API_URL"
    echo "IFACE: $IFACE"
    echo

    echo "=== SYSTEM ==="
    uname -a
    echo
    ip -br a
    echo
    ip r
    echo

    echo "=== WIREGUARD (SAFE) ==="
    wg show || true
    echo

    echo "=== WIREGUARD DUMP (MASKED) ==="
    wg show "$IFACE" dump 2>/dev/null | awk 'NR==1{$1="(hidden)"}1' || echo "wg dump failed"
    echo

    echo "=== API HEALTH ==="
    curl -sS "$API_URL/health" || echo "API is DOWN"
    echo

    echo "=== ROUTE AUDIT (WG) ==="
    if [[ -d "$REPO_ROOT/VpnService.Api/Controllers" ]]; then
      grep -R --line-number "admin/wg/state" "$REPO_ROOT/VpnService.Api/Controllers" || true
      grep -R --line-number "wg" "$REPO_ROOT/VpnService.Api/Controllers" || true
    else
      echo "Controllers directory not found: $REPO_ROOT/VpnService.Api/Controllers"
    fi
    echo
  } > "$REPORT_PATH" 2>&1

  echo "${GREEN}Report created:${NC} $REPORT_PATH"

  # If REPORT_GIT_COMMIT enabled, commit, cleanup and push. Otherwise skip VCS actions.
  if [[ "$REPORT_GIT_COMMIT" == "1" ]]; then
    cd "$REPO_ROOT" || return 1

    # Always add report even if reports/ is ignored
    git add -f "reports/$REPORT_NAME" "reports/.gitkeep" >/dev/null 2>&1 || true

    if git diff --cached --quiet; then
      echo "${YELLOW}Nothing staged for commit. Check .gitignore and report path.${NC}"
    else
      git commit -m "Diagnostic report: $REPORT_NAME"

      # Cleanup old reports and COMMIT deletions
      cleanup_reports_keep_last "$REPORT_KEEP" || true

      # Push with rebase fallback
      BR="$(git branch --show-current)"
      if git push origin "$BR"; then
        echo "${GREEN}Pushed to Git. On Windows: git pull -> open reports/.${NC}"
      else
        echo "${YELLOW}Push failed. Trying pull --rebase then push...${NC}"
        git pull --rebase origin "$BR" || true
        git push origin "$BR" || true
        echo "${GREEN}Pushed to Git. On Windows: git pull -> open reports/.${NC}"
      fi
    fi
  else
    echo "${YELLOW}REPORT_GIT_COMMIT=0 — skipping commit/cleanup/push.${NC}"
  fi

  pause
}

# ---------- CLI (non-interactive) ----------
handle_cli_mode() {
  case "${1:-}" in
    --full-audit)
      SKIP_PROMPTS=1
      run_full_audit
      exit 0
      ;;
    --full-audit-push)
      SKIP_PROMPTS=1
      REPORT_GIT_COMMIT=1
      run_full_audit
      exit 0
      ;;
    --help|-h)
      cat <<'EOF'
Usage: ./scripts/devmenu.sh [--full-audit] [--full-audit-push]

Options:
  --full-audit        Run the full audit once, write report, do not open menu.
  --full-audit-push   Same as --full-audit, but also commit and push report
                      (uses REPORT_GIT_COMMIT=1 internally).
  --help              Show this message.

Environment:
  REPORT_GIT_COMMIT=1   Auto-commit/push reports when available.
  SKIP_PROMPTS=1        Suppress pause prompts (set automatically for flags).
EOF
      exit 0
      ;;
    *)
      ;;
  esac
}

# ---------- Main loop ----------
handle_cli_mode "$@"

while true; do
  show_menu
  read -r -p "Select option: " opt </dev/tty || true

  case "$opt" in
    1)
      run_full_audit
      ;;
    2)
      report="$(report_name)"
      header "Running system diagnostics. Report: $report"
      system_diag "$report" || true
      echo "${GREEN}Report:${NC} $report"
      git_commit_report_if_enabled "$report" || true
      pause
      ;;
    3)
      report="$(report_name)"
      header "Running WireGuard diagnostics. Report: $report"
      wg_diag "$report" || true
      echo "${GREEN}Report:${NC} $report"
      git_commit_report_if_enabled "$report" || true
      pause
      ;;
    4)
      report="$(report_name)"
      header "Running git update. Report: $report"
      git_update "$report" || true
      echo "${GREEN}Report:${NC} $report"
      git_commit_report_if_enabled "$report" || true
      pause
      ;;
    5)
      report="$(report_name)"
      header "Running build. Report: $report"
      build_check "$report" || true
      echo "${GREEN}Report:${NC} $report"
      git_commit_report_if_enabled "$report" || true
      pause
      ;;
    6) api_menu ;;
    7)
      report="$(report_name)"
      header "Running smoke tests. Report: $report"
      smoke_auth_and_state "$report" || true
      echo "${GREEN}Report:${NC} $report"
      git_commit_report_if_enabled "$report" || true
      pause
      ;;
    8)
      report="$(report_name)"
      header "Running route audit. Report: $report"
      route_audit "$report" || true
      echo "${GREEN}Report:${NC} $report"
      git_commit_report_if_enabled "$report" || true
      pause
      ;;
    9)
      report="$(report_name)"
      header "Auth: login and save token. Report: $report"
      auth_and_save_token "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P1|p1)
      report="$(report_name)"
      header "Postgres up. Report: $report"
      pg_up "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P2|p2)
      report="$(report_name)"
      header "Postgres status. Report: $report"
      pg_status "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P3|p3)
      report="$(report_name)"
      header "Postgres logs. Report: $report"
      pg_logs "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P4|p4)
      report="$(report_name)"
      header "Postgres psql. Report: $report"
      pg_psql "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P5|p5)
      report="$(report_name)"
      header "Postgres down. Report: $report"
      pg_down "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P6|p6)
      report="$(report_name)"
      header "Postgres connection string. Report: $report"
      pg_print_conn "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    P7|p7)
      report="$(report_name)"
      header "Postgres diagnostics. Report: $report"
      pg_diag "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D1|d1)
      report="$(report_name)"
      header "DB status/health. Report: $report"
      db_run_action "$report" "db_status" db_status "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D2|d2)
      report="$(report_name)"
      header "DB diagnostics. Report: $report"
      db_run_action "$report" "db_diag" db_diag "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D3|d3)
      report="$(report_name)"
      header "DB psql shell. Report: $report"
      db_run_action "$report" "db_psql_shell" db_psql_shell "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D4|d4)
      report="$(report_name)"
      header "DB list databases. Report: $report"
      db_run_action "$report" "db_list_dbs" db_list_dbs "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D5|d5)
      report="$(report_name)"
      header "DB create database. Report: $report"
      db_run_action "$report" "db_create_db" db_create_db "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D6|d6)
      report="$(report_name)"
      header "DB drop database. Report: $report"
      db_run_action "$report" "db_drop_db" db_drop_db "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D7|d7)
      report="$(report_name)"
      header "DB ensure vpnservice DB + user. Report: $report"
      db_run_action "$report" "db_ensure_bootstrap" db_ensure_bootstrap "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D8|d8)
      report="$(report_name)"
      header "DB list tables. Report: $report"
      db_run_action "$report" "db_list_tables" db_list_tables "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    D9|d9)
      report="$(report_name)"
      header "DB backup. Report: $report"
      db_run_action "$report" "db_backup" db_backup "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    DA|da)
      report="$(report_name)"
      header "DB restore. Report: $report"
      db_run_action "$report" "db_restore" db_restore "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    DB|db)
      report="$(report_name)"
      header "DB active connections. Report: $report"
      db_run_action "$report" "db_show_connections" db_show_connections "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    DC|dc)
      report="$(report_name)"
      header "DB kill connections. Report: $report"
      db_run_action "$report" "db_kill_connections" db_kill_connections "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    S2|s2)
      report="$(report_name)"
      header "Stage 3.2 check (auth + reconcile). Report: $report"
      stage32_check "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    S3|s3)
      report="$(report_name)"
      header "Stage 3.3 check (auth + wg state). Report: $report"
      stage33_check "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    SA|sa)
      report="$(report_name)"
      header "Stage 3.2+3.3 full check. Report: $report"
      stage3233_check_all "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    A|a)
      report="$(report_name)"
      header "Probe: WG endpoints. Report: $report"
      probe_wg_endpoints "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    B|b)
      report="$(report_name)"
      header "Stage 3.2: dry-run reconcile. Report: $report"
      stage32_dry_run "$report" || true
      echo "${GREEN}Report:${NC} $report"
      pause
      ;;
    C|c)
      report="$(report_name)"
      header "Cleanup reports (keep last $REPORT_KEEP). Report: $report"
      {
        echo "Cleanup keep=$REPORT_KEEP"
        cd "$REPO_ROOT" || exit 1
        cleanup_reports_keep_last "$REPORT_KEEP"
        BR="$(git branch --show-current)"
        git push origin "$BR" || { git pull --rebase origin "$BR"; git push origin "$BR"; }
      } 2>&1 | tee -a "$report"
      pause
      ;;
    R)
      # Quick audit file and push for Windows users
      REPORT_FILE="$REPORT_DIR/audit_$(date +'%Y-%m-%d_%H-%M').txt"

      header "Сбор отчета и отправка на Windows"

      {
        echo "=== ОТЧЕТ ОТ $(date) ==="
        echo "Интерфейс: $IFACE"
        echo "WG Dump (masked):"
        wg show "$IFACE" dump 2>/dev/null | awk 'NR==1{$1="(hidden)"}1' || echo "wg dump failed"
        echo -e "\nПоследние логи API:"
        journalctl -u vpn-api --no-pager -n 20 2>/dev/null || echo "Logs not available"
      } > "$REPORT_FILE" 2>&1

      echo -e "${GREEN}Отчет создан: $REPORT_FILE${NC}"

      # Git Automation
      cd "$REPO_ROOT" || exit 1
      git add -f "$REPORT_FILE" >/dev/null 2>&1 || true

      if git diff --cached --quiet; then
        echo "${YELLOW}Nothing staged for commit.${NC}"
      else
        git commit -m "Auto-report: $(date +'%H:%M')" || true

        BR="$(git branch --show-current)"
        echo "Синхронизация с сервером..."
        git pull --rebase origin "$BR" || true
        git push origin "$BR" || true
        echo -e "${YELLOW}ГОТОВО. Теперь на Windows просто сделай 'git pull'${NC}"
      fi

      read -r -p "Нажмите Enter..." _ </dev/tty || true
      ;;
    L|l) list_reports; pause ;;
    0) exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
done
# ============================================================
