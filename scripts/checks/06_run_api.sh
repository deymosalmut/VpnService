#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/opt/vpn-service"
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:5272}"
HEALTH_URL="${HEALTH_URL:-${API_BASE_URL}/health}"
PORT="${API_PORT:-5272}"

echo "----------------------------------------"
echo "[INFO] RUN API (idempotent)"
echo "[INFO] API_BASE_URL=${API_BASE_URL}"
echo "[INFO] HEALTH_URL=${HEALTH_URL}"
echo "----------------------------------------"

wait_for_api() {
  local tries="${1:-80}"
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
  ss -lntp 2>/dev/null | grep ":${PORT} " || true
  exit 1
fi

# 3) Start API in background
echo "[INFO] Starting API in background..."
LOG_DIR="${ROOT_DIR}/reports"
mkdir -p "$LOG_DIR"
RUN_LOG="${LOG_DIR}/api_run_$(date -u +%Y%m%d_%H%M%SZ).log"

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
exit 1
