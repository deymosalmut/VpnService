#!/usr/bin/env bash
set -Eeuo pipefail

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

# ---------- Postgres (Docker) defaults (override via env) ----------
# Compose/env expected at $PG_COMPOSE_FILE and $PG_ENV_FILE.
export PG_CONTAINER="${PG_CONTAINER:-vpnservice-postgres}"
export PG_DB="${PG_DB:-vpnservice}"
export PG_USER="${PG_USER:-vpnservice}"
export PG_PASSWORD="${PG_PASSWORD:-vpnservice_pwd}"
export PG_PORT="${PG_PORT:-5432}"
export PG_VOLUME="${PG_VOLUME:-vpnservice_pgdata}"
export PG_COMPOSE_FILE="${PG_COMPOSE_FILE:-$REPO_ROOT/infra/postgres/docker-compose.yml}"
export PG_ENV_FILE="${PG_ENV_FILE:-$REPO_ROOT/infra/postgres/.env}"

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
  echo "ConnectionStrings__Default=Host=localhost;Port=$PG_PORT;Database=$PG_DB;Username=$PG_USER;Password=$PG_PASSWORD" \
    | tee -a "$log" >/dev/null
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
