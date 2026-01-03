#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "BUILD CHECK"
need_cmd dotnet

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

log "dotnet restore..."
dotnet restore

log "dotnet build..."
dotnet build -c Debug

hr; log "OK"
