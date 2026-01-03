#!/usr/bin/env bash
set -Eeuo pipefail

# --- Конфигурация ---
export PROJ="${PROJ:-/opt/vpn-service/VpnService}"
export API_URL="${API_URL:-http://localhost:5272}"
export IFACE="${IFACE:-wg1}"

REPORT_DIR="${HOME}/vpn_reports"
mkdir -p "$REPORT_DIR"

# Файлы состояния
PID_FILE="${REPORT_DIR}/api.pid"
LAST_TOKEN_FILE="${REPORT_DIR}/last_token.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_report_name() {
  echo "$REPORT_DIR/report_$(date +'%Y-%m-%d_%H-%M-%S').log"
}

header() {
  echo -e "\n${YELLOW}>>> $1${NC}"
}

pause() {
  read -r -p "Нажмите Enter..."
}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: '$1' не найден. Установи пакет/утилиту.${NC}"
    return 1
  }
}

log_block() {
  local task="$1"
  local log="$2"
  {
    echo "-------------------------------------------"
    echo "TASK: $task"
    echo "TIME: $(date)"
    echo "-------------------------------------------"
  } | tee -a "$log"
}

run_and_log() {
  local task="$1"; local log="$2"; shift 2
  log_block "$task" "$log"
  # выполняем команду безопасно (без eval)
  "$@" 2>&1 | tee -a "$log"
  echo | tee -a "$log" >/dev/null
}

api_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1
}

api_start_bg() {
  local log="$1"
  if api_running; then
    echo -e "${YELLOW}API уже запущен PID=$(cat "$PID_FILE"). Сначала останови.${NC}" | tee -a "$log"
    return 0
  fi

  run_and_log "API: start background" "$log" bash -lc "
    cd '$PROJ'
    nohup dotnet run --project VpnService.Api > '$log.api.out' 2>&1 &
    echo \$! > '$PID_FILE'
    echo 'PID=' \$(cat '$PID_FILE')
  "

  # Подождём и дернем health
  sleep 1
  run_and_log "API: health probe" "$log" curl -sS "$API_URL/health"
}

api_stop() {
  local log="$1"
  if ! api_running; then
    echo -e "${YELLOW}API не запущен.${NC}" | tee -a "$log"
    return 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  run_and_log "API: stop (PID=$pid)" "$log" bash -lc "
    kill $pid || true
    sleep 1
    kill -9 $pid 2>/dev/null || true
    rm -f '$PID_FILE'
    echo 'stopped'
  "
}

api_run_fg() {
  # foreground без отчёта — чтобы видно было живой лог
  cd "$PROJ"
  dotnet run --project VpnService.Api
}

get_token() {
  # Печатает token в stdout. Если не удалось — пусто.
  local login_json
  login_json="$(curl -sS -X POST "$API_URL/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin123"}' || true)"

  # если это не json/ошибка — вернем пусто
  echo "$login_json" | python3 - <<'PY' 2>/dev/null || true
import sys, json
try:
    data=json.load(sys.stdin)
    print(data.get("accessToken",""))
except Exception:
    print("")
PY
}

system_diag() {
  local log="$1"
  run_and_log "System: whoami/hostname/date" "$log" bash -lc 'whoami; hostname; date'
  run_and_log "System: timedatectl (top)" "$log" bash -lc 'timedatectl | sed -n "1,10p"'
  run_and_log "Network: ip -br a" "$log" bash -lc 'ip -br a'
  run_and_log "Network: routes" "$log" bash -lc 'ip r'
  run_and_log "Network: ping 8.8.8.8" "$log" bash -lc 'ping -c 1 8.8.8.8'
}

wg_diag() {
  local log="$1"
  need wg || return 1
  run_and_log "WireGuard: wg show" "$log" bash -lc 'sudo wg show'
  run_and_log "WireGuard: wg show dump" "$log" bash -lc "sudo wg show '$IFACE' dump | head -n 30"
}

git_update() {
  local log="$1"
  run_and_log "Git: status" "$log" bash -lc "cd '$PROJ' && git status"
  run_and_log "Git: fetch --all --prune" "$log" bash -lc "cd '$PROJ' && git fetch --all --prune"
  run_and_log "Git: pull --rebase" "$log" bash -lc "cd '$PROJ' && git pull --rebase"
  run_and_log "Git: log -5" "$log" bash -lc "cd '$PROJ' && git log -5 --oneline"
}

build_check() {
  local log="$1"
  need dotnet || return 1
  run_and_log "Build: dotnet --info (top)" "$log" bash -lc "dotnet --info | sed -n '1,25p'"
  run_and_log "Build: clean" "$log" bash -lc "cd '$PROJ' && dotnet clean"
  run_and_log "Build: remove bin/obj" "$log" bash -lc "cd '$PROJ' && find . -type d \\( -name bin -o -name obj \\) -prune -exec rm -rf {} +"
  run_and_log "Build: restore" "$log" bash -lc "cd '$PROJ' && dotnet restore"
  run_and_log "Build: build Debug" "$log" bash -lc "cd '$PROJ' && dotnet build -c Debug"
}

route_audit() {
  local log="$1"
  run_and_log "Route audit: WireGuard controllers/classes" "$log" bash -lc "
    cd '$PROJ'
    grep -R --line-number 'class .*WireGuard' VpnService.Api/Controllers || true
  "
  run_and_log "Route audit: admin/wg/state routes" "$log" bash -lc "
    cd '$PROJ'
    grep -R --line-number 'admin/wg/state' VpnService.Api/Controllers || true
    grep -R --line-number '\\[Route' VpnService.Api/Controllers | grep -i wg || true
  "
}

smoke_auth_and_state() {
  local log="$1"
  need curl || return 1
  need python3 || return 1

  run_and_log "Smoke: health" "$log" curl -sS "$API_URL/health"

  log_block "Smoke: login and token" "$log"
  local token
  token="$(get_token)"

  if [[ -z "${token:-}" ]]; then
    echo -e "${RED}ERROR: token пустой. Проверь /api/v1/auth/login и лог API.${NC}" | tee -a "$log"
    echo "Подсказка: открой swagger или проверь DTO для LoginRequest." | tee -a "$log"
    return 1
  fi

  echo "$token" > "$LAST_TOKEN_FILE"
  echo -e "TOKEN(short): ${token:0:25}..." | tee -a "$log"
  echo | tee -a "$log" >/dev/null

  run_and_log "Smoke: WG state (protected)" "$log" bash -lc "
    curl -sS '$API_URL/api/v1/admin/wg/state?iface=$IFACE' \
      -H 'Authorization: Bearer $token'
  "
}

list_reports() {
  header "Последние отчеты ($REPORT_DIR)"
  ls -lh "$REPORT_DIR" | tail -n 20
}

show_menu() {
  clear
  echo "=========================================="
  echo "   VPN SERVICE DEV MENU + REPORTING       "
  echo "=========================================="
  echo "1) [Full Audit] Прогнать всё и создать отчет"
  echo "2) [Diag] Проверка системы"
  echo "3) [WG] Проверка WireGuard"
  echo "4) [Git] Обновить проект (fetch/pull)"
  echo "5) [Build] Сборка (clean/restore/build)"
  echo "6) [API] Управление API (fg/bg/stop)"
  echo "7) [Smoke] Тест API (Auth + State)"
  echo "8) [Routes] Route audit (ловим AmbiguousMatch)"
  echo "L) [Logs] Посмотреть список отчетов"
  echo "0) Выход"
  echo "=========================================="
}

while true; do
  show_menu
  read -r -p "Выберите действие: " opt
  case "$opt" in
    1)
      REPORT="$(get_report_name)"
      header "Запуск полного аудита... Отчет: $REPORT"

      system_diag "$REPORT" || true
      wg_diag "$REPORT" || true
      git_update "$REPORT" || true
      build_check "$REPORT" || true
      route_audit "$REPORT" || true
      smoke_auth_and_state "$REPORT" || true

      echo -e "${GREEN}Отчет сформирован: $REPORT${NC}"
      pause
      ;;
    2)
      REPORT="$(get_report_name)"
      header "Diag... Отчет: $REPORT"
      system_diag "$REPORT" || true
      echo -e "${GREEN}Отчет: $REPORT${NC}"
      pause
      ;;
    3)
      REPORT="$(get_report_name)"
      header "WG... Отчет: $REPORT"
      wg_diag "$REPORT" || true
      echo -e "${GREEN}Отчет: $REPORT${NC}"
      pause
      ;;
    4)
      REPORT="$(get_report_name)"
      header "Git update... Отчет: $REPORT"
      git_update "$REPORT" || true
      echo -e "${GREEN}Отчет: $REPORT${NC}"
      pause
      ;;
    5)
      REPORT="$(get_report_name)"
      header "Build... Отчет: $REPORT"
      build_check "$REPORT" || true
      echo -e "${GREEN}Отчет: $REPORT${NC}"
      pause
      ;;
    6)
      clear
      echo "------------------------------------------"
      echo "API control (API_URL=$API_URL)"
      echo "------------------------------------------"
      echo "1) Run API foreground (Ctrl+C to stop)"
      echo "2) Start API in background"
      echo "3) Stop background API"
      echo "0) Back"
      read -r -p "Select: " a
      REPORT="$(get_report_name)"
      case "$a" in
        1) api_run_fg ;;
        2) api_start_bg "$REPORT"; echo -e "${GREEN}Лог: $REPORT.api.out${NC}"; pause ;;
        3) api_stop "$REPORT"; pause ;;
        0) : ;;
        *) echo "Неверный выбор"; sleep 1 ;;
      esac
      ;;
    7)
      REPORT="$(get_report_name)"
      header "Smoke Test... Отчет: $REPORT"
      smoke_auth_and_state "$REPORT" || true
      echo -e "${GREEN}Отчет: $REPORT${NC}"
      pause
      ;;
    8)
      REPORT="$(get_report_name)"
      header "Route audit... Отчет: $REPORT"
      route_audit "$REPORT" || true
      echo -e "${GREEN}Отчет: $REPORT${NC}"
      pause
      ;;
    L|l)
      list_reports
      pause
      ;;
    0) exit 0 ;;
    *) echo "Неверный выбор"; sleep 1 ;;
  esac
done
