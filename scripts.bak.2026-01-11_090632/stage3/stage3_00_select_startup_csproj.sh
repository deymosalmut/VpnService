#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

LOCAL_ENV_DIR="$REPO_ROOT/infra/local"
LOCAL_ENV_FILE="$LOCAL_ENV_DIR/app.env"

mkdir -p "$LOCAL_ENV_DIR"

# find csproj candidates
mapfile -t projects < <(find . -maxdepth 4 -name "*.csproj" | sort)

if [[ "${#projects[@]}" -eq 0 ]]; then
  echo "ERROR: no .csproj found" >&2
  exit 2
fi

# default: Api project if exists
default="./VpnService.Api/VpnService.Api.csproj"
selected=""
if [[ -f "$default" ]]; then
  selected="$default"
else
  selected="${projects[0]}"
fi

echo ">>> Select EF startup project (.csproj)"
echo "Candidates:"
printf ' - %s\n' "${projects[@]}"
echo
echo "Selected (default): $selected"
echo

# allow override via env var, still non-interactive
if [[ -n "${APP_CSPROJ_OVERRIDE:-}" ]]; then
  if [[ -f "$APP_CSPROJ_OVERRIDE" ]]; then
    selected="$APP_CSPROJ_OVERRIDE"
    echo "Override via APP_CSPROJ_OVERRIDE: $selected"
  else
    echo "ERROR: APP_CSPROJ_OVERRIDE not found: $APP_CSPROJ_OVERRIDE" >&2
    exit 3
  fi
fi

# write local env (gitignored directory already used in your repo)
{
  echo "# local app settings (gitignored)"
  echo "export APP_CSPROJ=\"$selected\""
} > "$LOCAL_ENV_FILE"

chmod 640 "$LOCAL_ENV_FILE" || true

echo "OK saved: $LOCAL_ENV_FILE"
echo "Next: scripts will source it automatically."
