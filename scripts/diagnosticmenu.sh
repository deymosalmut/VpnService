#!/usr/bin/env bash
set -Eeuo pipefail

# diagnosticmenu.sh — Permission + Postgres bootstrap diagnostics for VPN Service
# - Creates a report under reports/
# - Offers fixes for common "permission denied" cases
# - Optional git add/commit/push ONLY the report file (with explicit yes/no)

# ---------- UI ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

header() { echo -e "\n${YELLOW}>>> $1${NC}"; }
ok()     { echo -e "${GREEN}OK:${NC} $1"; }
warn()   { echo -e "${YELLOW}WARN:${NC} $1"; }
err()    { echo -e "${RED}ERROR:${NC} $1"; }

# ---------- Repo root detection ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Reports
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/reports}"
mkdir -p "$REPORT_DIR" 2>/dev/null || true
REPORT_FILE="$REPORT_DIR/diagnostic_$(date +'%Y-%m-%d_%H-%M-%S').log"

# Git
GIT_REMOTE_DEFAULT="${GIT_REMOTE_DEFAULT:-origin}"

# ---------- Logging ----------
log() { echo "$*" | tee -a "$REPORT_FILE" >/dev/null; }
run() {
  local title="$1"; shift
  header "$title" | tee -a "$REPORT_FILE"
  log "CMD: $*"
  # shellcheck disable=SC2068
  if "$@" 2>&1 | tee -a "$REPORT_FILE"; then
    log "STATUS: 0"
    return 0
  else
    local rc=$?
    log "STATUS: $rc"
    return $rc
  fi
}

# ---------- Helpers ----------
ask_yes_no() {
  local prompt="$1"
  while true; do
    read -r -p "$prompt (yes/no): " ans
    case "${ans,,}" in
      yes|y) return 0 ;;
      no|n)  return 1 ;;
      *) echo "Please type yes or no." ;;
    esac
  done
}

repo_relpath() {
  local abs="$1"
  python3 - <<'PY' "$REPO_ROOT" "$abs"
import os,sys
root=os.path.abspath(sys.argv[1])
p=os.path.abspath(sys.argv[2])
print(os.path.relpath(p, root))
PY
}

git_ok() {
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

current_branch() {
  git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "main"
}

git_commit_report_interactive() {
  local report_abs="$1"
  local tag="${2:-diagnostic}"
  local report_rel
  report_rel="$(repo_relpath "$report_abs")"

  if ! git_ok; then
    err "Not a git repo: $REPO_ROOT (skip commit/push)"
    return 1
  fi

  header "Git: stage/commit/push report (interactive)" | tee -a "$REPORT_FILE"
  log "Report: $report_rel"

  if ! ask_yes_no "Do you want to git add/commit/push ONLY this report file?"; then
    warn "Skipped git commit/push by user choice."
    return 0
  fi

  # Ensure no accidental staging leaks: stage forced only this file, then commit --only it
  run "Git: add (forced) report only" git -C "$REPO_ROOT" add -f -- "$report_rel"

  local msg="report: ${tag} $(basename "$report_rel")"
  run "Git: commit report only" git -C "$REPO_ROOT" commit -m "$msg" --only -- "$report_rel" || {
    warn "Commit may have failed (nothing to commit?). Continuing."
  }

  local br
  br="$(current_branch)"
  # Try push, then rebase+push
  if run "Git: push" git -C "$REPO_ROOT" push "$GIT_REMOTE_DEFAULT" "$br"; then
    ok "Report pushed."
    return 0
  fi

  warn "Push failed; attempting pull --rebase then push..."
  run "Git: pull --rebase" git -C "$REPO_ROOT" pull --rebase "$GIT_REMOTE_DEFAULT" "$br" || true
  run "Git: push after rebase" git -C "$REPO_ROOT" push "$GIT_REMOTE_DEFAULT" "$br" || true
}

# ---------- Checks / Fixes ----------
check_paths_and_perms() {
  header "Check: paths and permissions" | tee -a "$REPORT_FILE"
  log "REPO_ROOT=$REPO_ROOT"
  log "REPORT_DIR=$REPORT_DIR"
  run "Whoami / ID / PWD" bash -lc 'whoami && id && pwd'
  run "List repo root" bash -lc "ls -ld '$REPO_ROOT' '$REPORT_DIR' || true"
  run "List scripts" bash -lc "ls -la '$REPO_ROOT/scripts' | sed -n '1,120p' || true"
  run "Devmenu exec bit" bash -lc "ls -la '$REPO_ROOT/scripts/devmenu.sh' || true"
}

fix_reports_permissions() {
  header "Fix: reports/ ownership and permissions" | tee -a "$REPORT_FILE"
  local user group
  user="$(id -un)"
  group="$(id -gn)"
  run "Create reports dir" bash -lc "sudo mkdir -p '$REPORT_DIR' || mkdir -p '$REPORT_DIR'"
  # Prefer user ownership (so devmenu runs without root)
  run "Chown reports to current user" bash -lc "sudo chown -R '$user:$group' '$REPORT_DIR' || true"
  run "Ensure user rwX on reports" bash -lc "chmod -R u+rwX '$REPORT_DIR' || true"
  run "Verify reports perms" bash -lc "ls -ld '$REPORT_DIR' && touch '$REPORT_DIR/.perm_test' && rm -f '$REPORT_DIR/.perm_test'"
}

fix_devmenu_exec_bit() {
  header "Fix: make devmenu executable" | tee -a "$REPORT_FILE"
  run "chmod +x devmenu.sh" bash -lc "chmod +x '$REPO_ROOT/scripts/devmenu.sh' && ls -la '$REPO_ROOT/scripts/devmenu.sh'"
}

check_sudo_and_psql() {
  header "Check: sudo + psql + postgres access" | tee -a "$REPORT_FILE"
  run "Which psql / version" bash -lc "which psql && psql --version"
  run "sudo non-interactive check" bash -lc "sudo -n true && echo 'sudo: OK (no password)' || echo 'sudo: needs password or not allowed'"
  run "Test sudo -u postgres psql" bash -lc "sudo -u postgres psql -c 'select 1;'"
}

check_pg_hba_and_service() {
  header "Check: postgres service + hba_file" | tee -a "$REPORT_FILE"
  run "systemctl status postgresql" bash -lc "systemctl status postgresql --no-pager | sed -n '1,80p' || true"
  run "Show hba_file path" bash -lc "sudo -u postgres psql -c \"SHOW hba_file;\""
  run "Show listen ports 5432/5433" bash -lc "ss -lntp 2>/dev/null | { grep ':5432' || true; grep ':5433' || true; } || true"
}

db_bootstrap_vpnservice() {
  header "DB bootstrap: ensure vpnservice role + db (system postgres)" | tee -a "$REPORT_FILE"
  warn "This runs via: sudo -u postgres psql"
  warn "Password will NOT be printed; it will be set to 'vpnservice_pwd' by default."

  local pg_user="${PG_USER:-vpnservice}"
  local pg_db="${PG_DB:-vpnservice}"
  local pg_pwd="${PG_PASSWORD:-vpnservice_pwd}"

  # Mask password in report
  local masked="${pg_pwd:0:2}***"
  log "Target role: $pg_user"
  log "Target db:   $pg_db"
  log "Password:   $masked"

  # Idempotent block
  run "Ensure role + password" bash -lc "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
\"DO \\$\\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${pg_user}') THEN
    CREATE ROLE ${pg_user} LOGIN PASSWORD '${pg_pwd}';
  ELSE
    ALTER ROLE ${pg_user} WITH PASSWORD '${pg_pwd}';
  END IF;
END \\$\\$;\""

  run "Ensure DB exists" bash -lc "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
\"DO \\$\\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${pg_db}') THEN
    CREATE DATABASE ${pg_db} OWNER ${pg_user};
  END IF;
END \\$\\$;\""

  run "Set DB owner + privileges" bash -lc "sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
\"ALTER DATABASE ${pg_db} OWNER TO ${pg_user};
GRANT ALL PRIVILEGES ON DATABASE ${pg_db} TO ${pg_user};\""

  run "Verify owner" bash -lc "sudo -u postgres psql -c \"\\l ${pg_db}\""
}

test_login_as_service_user() {
  header "Test: connect as vpnservice user (password auth)" | tee -a "$REPORT_FILE"
  local pg_user="${PG_USER:-vpnservice}"
  local pg_db="${PG_DB:-vpnservice}"
  local pg_port="${PG_PORT:-5432}"
  # Do not echo password. Use PGPASSWORD env for the command only.
  run "psql connect test" bash -lc "PGPASSWORD='${PG_PASSWORD:-vpnservice_pwd}' psql -h 127.0.0.1 -p '${pg_port}' -U '${pg_user}' -d '${pg_db}' -c 'select current_user, current_database();'"
}

# ---------- Menu ----------
show_menu() {
  echo
  echo "================ DIAGNOSTIC MENU ================"
  echo "Repo:    $REPO_ROOT"
  echo "Report:  $REPORT_FILE"
  echo "------------------------------------------------"
  echo "1) Check paths/perms (repo, reports, devmenu)"
  echo "2) Fix reports/ permissions (common D7 permission denied)"
  echo "3) Fix devmenu executable bit"
  echo "4) Check sudo + psql + sudo -u postgres"
  echo "5) Check postgres service + pg_hba + ports"
  echo "6) DB bootstrap (create role/db vpnservice idempotent)"
  echo "7) Test login as vpnservice (psql using password)"
  echo "8) Offer git commit/push report (yes/no)"
  echo "9) Run ALL (1 -> 7) and then offer commit"
  echo "0) Exit"
  echo "================================================"
}

main() {
  header "Diagnostic session started"
  log "TIME_UTC: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  log "HOST: $(hostname)"
  log "USER: $(whoami)"
  log "------------------------------------------------"

  while true; do
    show_menu
    read -r -p "Select option: " opt
    case "$opt" in
      1) check_paths_and_perms ;;
      2) fix_reports_permissions ;;
      3) fix_devmenu_exec_bit ;;
      4) check_sudo_and_psql ;;
      5) check_pg_hba_and_service ;;
      6) db_bootstrap_vpnservice ;;
      7) test_login_as_service_user ;;
      8) git_commit_report_interactive "$REPORT_FILE" "diagnosticmenu" ;;
      9)
        check_paths_and_perms || true
        fix_reports_permissions || true
        fix_devmenu_exec_bit || true
        check_sudo_and_psql || true
        check_pg_hba_and_service || true
        db_bootstrap_vpnservice || true
        test_login_as_service_user || true
        git_commit_report_interactive "$REPORT_FILE" "diagnosticmenu-all"
        ;;
      0) break ;;
      *) echo "Unknown option." ;;
    esac
  done

  header "Done. Report saved: $REPORT_FILE"
}

main "$@"
