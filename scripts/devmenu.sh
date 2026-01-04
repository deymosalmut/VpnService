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
export API_PORT="${API_PORT:-${API_URL##*:}}"

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repo root (one level above scripts/)
export REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Project root = repo root
export PROJ="$REPO_ROOT"

# Reports inside repo
export REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR"

# State files
PID_FILE="$REPORT_DIR/api.pid"
LAST_TOKEN_FILE="$REPORT_DIR/last_token.txt"

# Optional behavior
# If REPORT_GIT_COMMIT=1 -> auto-commit report file to current repo
export REPORT_GIT_COMMIT="${REPORT_GIT_COMMIT:-0}"

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
    if ss -ltnp 2>/dev/null | grep -q ":$API_PORT"; then
      echo "${YELLOW}API port $API_PORT already in use. Not starting a second instance.${NC}" | tee -a "$log" >/dev/null
      ss -ltnp | grep ":$API_PORT" | tee -a "$log" >/dev/null || true
      return 0
    fi

    nohup dotnet run --project VpnService.Api >"$api_out" 2>&1 &
    echo $! >"$PID_FILE"
  )

  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  echo "Started API background PID=$pid" | tee -a "$log" >/dev/null
  echo "API stdout/stderr: $api_out" | tee -a "$log" >/dev/null

  # Health probe (retry up to ~10s)
  log_block "API: health probe" "$log"
  local ok=0
  for _ in {1..10}; do
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

  local resp token
  resp="$(curl -sS -X POST "$API_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" || true)"

  if command -v python3 >/dev/null 2>&1; then
    token="$(printf '%s' "$resp" | python3 - <<'PY' 2>/dev/null || true
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get("accessToken",""))
except Exception:
    print("")
PY
)"
  else
    # very small fallback (not perfect JSON parsing but OK for accessToken field)
    token="$(printf '%s' "$resp" | sed -n 's/.*"accessToken"[[:space:]]*:[[:space:]]*"\([^\"]*\)".*/\1/p')"
  fi

  printf '%s' "$token"
}

auth_and_save_token() {
  local log="$1"
  need curl

  run_and_log "Auth: health check" "$log" curl -fsS "$API_URL/health"

  log_block "Auth: login (get token)" "$log"
  local token
  token="$(get_token)"

  if [[ -z "${token:-}" ]]; then
    echo "${RED}ERROR:${NC} token is empty. Check credentials or /api/v1/auth/login." | tee -a "$log" >/dev/null
    return 1
  fi

  echo "$token" > "$LAST_TOKEN_FILE"
  echo "Token saved: $LAST_TOKEN_FILE" | tee -a "$log" >/dev/null
  echo "Token preview: ${token:0:25}..." | tee -a "$log" >/dev/null
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
A) [Probe] Probe WG endpoints
B) [Stage3.2] Dry-run reconcile (if endpoint exists)
C) [Reports] Cleanup reports (keep last N)
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

# ---------- Main loop ----------
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
    L|l) list_reports; pause ;;
    0) exit 0 ;;
    *) echo "Invalid choice."; sleep 1 ;;
  esac
done
# ============================================================