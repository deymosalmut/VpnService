#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/opt/vpn-service"
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:5272}"
HEALTH_URL="${HEALTH_URL:-${API_BASE_URL}/health}"
PORT="${API_PORT:-5272}"

<<<<<<< HEAD
hr; log "RUN API (idempotent)"
log "API_BASE_URL=$API_BASE_URL"

need_cmd curl
need_cmd dotnet

health_url="${API_BASE_URL%/}/health"

api_status() {
  curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$health_url" 2>/dev/null || echo "000"
}

wait_for_api() {
  local timeout="${API_READY_TIMEOUT:-30}"
  local interval="${API_READY_INTERVAL:-1}"
  local elapsed=0

  log "Waiting for API readiness at $health_url (timeout ${timeout}s)"
  while true; do
    local status
    status="$(api_status)"
    if [[ "$status" == "200" ]]; then
      log "API ready (HTTP 200)"
      return 0
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
    if (( elapsed >= timeout )); then
      err "API not ready after ${timeout}s (last HTTP $status)"
      return 1
    fi
  done
}

parse_host_port() {
  local base="$1"
  local scheme host_port host port

  scheme="${base%%://*}"
  if [[ "$scheme" == "$base" ]]; then
    scheme="http"
  fi

  host_port="${base#*://}"
  host_port="${host_port%%/*}"
  host="${host_port%%:*}"
  port="${host_port##*:}"

  if [[ "$host_port" == "$host" ]]; then
    if [[ "$scheme" == "https" ]]; then
      port="443"
    else
      port="80"
    fi
  fi

  echo "$host" "$port"
}

port_in_use() {
  local host="$1"
  local port="$2"
  (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
}

if [[ "$(api_status)" == "200" ]]; then
  log "API already responding at $health_url"
  hr; log "OK"
  exit 0
fi

read -r host port < <(parse_host_port "$API_BASE_URL")
if [[ -n "$host" && -n "$port" ]] && port_in_use "$host" "$port"; then
  err "Port $port on $host is already in use, but $health_url did not return 200."
  err "Stop the conflicting process or set API_BASE_URL to the running API."
  exit 1
fi

api_log="${API_RUN_LOG:-/tmp/vpnservice_api.log}"
log "Starting API in background (log: $api_log)"
dotnet run --project VpnService.Api >"$api_log" 2>&1 &
api_pid=$!
log "API pid: $api_pid"

if wait_for_api; then
  hr; log "OK"
  exit 0
fi

err "API failed to become ready. Check $api_log"
=======
echo "----------------------------------------"
echo "[INFO] RUN API (idempotent)"
echo "[INFO] API_BASE_URL=${API_BASE_URL}"
echo "[INFO] HEALTH_URL=${HEALTH_URL}"
echo "----------------------------------------"

wait_for_api() {
  local tries="${1:-40}"
  local sleep_s="${2:-0.25}"
  local i=1
  while [ "$i" -le "$tries" ]; do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
      echo "[INFO] API is ready (health OK)"
      return 0
    fi
    sleep "$sleep_s"
    i=$((i+1))
  done
  return 1
}

# 1) If API already responding -> OK
if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
  echo "[INFO] API already responding; skipping start"
  echo "----------------------------------------"
  echo "[INFO] OK"
  exit 0
fi

# 2) If port is already in use but health not responding -> fail (wrong process)
if ss -lntp 2>/dev/null | grep -q ":${PORT} "; then
  echo "[ERR ] Port ${PORT} is in use, but ${HEALTH_URL} is not responding."
  echo "[ERR ] Stop the process on :${PORT} or fix HEALTH_URL/API_BASE_URL."
  ss -lntp | grep ":${PORT} " || true
  exit 1
fi

# 3) Start API in background
echo "[INFO] Starting API in background..."
LOG_DIR="${ROOT_DIR}/reports"
mkdir -p "$LOG_DIR"
RUN_LOG="${LOG_DIR}/api_run_$(date -u +%Y%m%d_%H%M%SZ).log"

# Ensure we run from repo root, with same launch profile behavior as before
cd "$ROOT_DIR"

nohup dotnet run --project "${ROOT_DIR}/VpnService.Api/VpnService.Api.csproj" \
  >"$RUN_LOG" 2>&1 &

PID=$!
echo "$PID" > "${LOG_DIR}/api_last_pid.txt"
echo "[INFO] dotnet run PID=${PID}"
echo "[INFO] stdout/stderr -> ${RUN_LOG}"

# 4) Wait for readiness
if wait_for_api 80 0.25; then
  echo "----------------------------------------"
  echo "[INFO] OK"
  exit 0
fi

echo "[ERR ] API did not become ready in time."
echo "[ERR ] Last 60 lines of ${RUN_LOG}:"
tail -n 60 "$RUN_LOG" || true
>>>>>>> b837a0a (Fix /admin HEAD and make 06_run_api.sh idempotent)
exit 1
