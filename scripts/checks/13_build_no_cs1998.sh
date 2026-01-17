#!/usr/bin/env bash
# PURPOSE: Ensure Debug build of VpnService.Api does not trigger CS1998 warnings
# EXPECTED OUTPUT: Build succeeds, no CS1998 in output
# EXIT CODE: 0 on success, 1 on failure

# Fail fast if /bin/bash is missing (should not happen, but explicit)
[[ -x /bin/bash ]] || { echo "[ERR ] /bin/bash not found" >&2; exit 1; }

set -Eeuo pipefail
source "$(dirname "$0")/../lib/common.sh"

hr; log "BUILD NO CS1998 CHECK"

need_cmd dotnet
need_cmd bash

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
log "Root directory: $ROOT"

cd "$ROOT"

build_output=""
build_status=0

log "Building VpnService.Api (Debug)..."
set +e
build_output="$(dotnet build VpnService.Api/VpnService.Api.csproj -c Debug 2>&1)"
build_status=$?
set -e

# Print full output for inspection
printf '%s\n' "$build_output"

# Check for CS1998 using grep (fastest, no external deps)
if printf '%s\n' "$build_output" | grep -q "CS1998"; then
  hr; err "FAIL: CS1998 warning detected in build output"
  exit 1
fi

# Check build status
if [[ "$build_status" -ne 0 ]]; then
  hr; err "FAIL: dotnet build exited with code $build_status"
  exit "$build_status"
fi

hr; log "✓ PASS: Build succeeded, no CS1998"
exit 0
