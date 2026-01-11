#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "BUILD NO CS1998 CHECK"
need_cmd dotnet

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

build_output=""
build_status=0

set +e
build_output="$(dotnet build VpnService.Api/VpnService.Api.csproj -c Debug 2>&1)"
build_status=$?
set -e

printf '%s\n' "$build_output"

if command -v rg >/dev/null 2>&1; then
  if printf '%s\n' "$build_output" | rg -q "CS1998"; then
    hr; err "CS1998 warning detected in build output."
    exit 1
  fi
else
  if printf '%s\n' "$build_output" | grep -q "CS1998"; then
    hr; err "CS1998 warning detected in build output."
    exit 1
  fi
fi

if [[ "$build_status" -ne 0 ]]; then
  hr; err "dotnet build failed."
  exit "$build_status"
fi

hr; log "OK (no CS1998)"
