#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

hr; log "RUN API (foreground)"
log "API_BASE_URL=$API_BASE_URL"
log "Press Ctrl+C to stop"

dotnet run --project VpnService.Api
