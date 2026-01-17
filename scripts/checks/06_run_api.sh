#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

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
exit 1
