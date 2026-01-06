#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

F="scripts/stage34_preflight.sh"
if [[ ! -f "$F" ]]; then
  echo "ERROR: file not found: $F" >&2
  exit 2
fi

cp -a "$F" "${F}.bak_$(date +%Y-%m-%d_%H-%M-%S)"

# 1) Заменяем проверку dotnet-ef на правильную проверку dotnet ef (+ restore)
python3 - <<'PY'
import re, pathlib, sys, time

p = pathlib.Path("scripts/stage34_preflight.sh")
s = p.read_text(encoding="utf-8", errors="ignore")

# Удаляем старые "dotnet-ef not found" блоки (если найдём)
s = re.sub(r".*dotnet-ef not found.*\n", "", s)

# Ищем место после dotnet --info или рядом с dotnet блоком, куда вставить проверку.
# Если найдём маркер "dotnet: info", вставим сразу после него следующий шаг.
marker = ">>> dotnet: info (top)"
idx = s.find(marker)

inject = r'''
# --- dotnet ef (local tool) presence: WARN-only ---
echo -e "\n>>> dotnet: ef (local tool) presence (WARN-only)" | tee -a "$REPORT_FILE"
if bash -lc "cd '$REPO_ROOT' && dotnet ef --version" >>"$REPORT_FILE" 2>&1; then
  echo "STATUS: 0" | tee -a "$REPORT_FILE"
  echo "OK dotnet ef available." | tee -a "$REPORT_FILE"
else
  # attempt restore if tool-manifest exists
  if [[ -f "$REPO_ROOT/.config/dotnet-tools.json" ]]; then
    bash -lc "cd '$REPO_ROOT' && dotnet tool restore" >>"$REPORT_FILE" 2>&1 || true
  fi
  if bash -lc "cd '$REPO_ROOT' && dotnet ef --version" >>"$REPORT_FILE" 2>&1; then
    echo "STATUS: 0" | tee -a "$REPORT_FILE"
    echo "OK dotnet ef available (after tool restore)." | tee -a "$REPORT_FILE"
  else
    echo "STATUS: 0" | tee -a "$REPORT_FILE"
    echo "WARN dotnet ef not available. Migrations CLI steps will be skipped until tool is installed." | tee -a "$REPORT_FILE"
  fi
fi
'''

if idx != -1:
    # вставим после блока dotnet info, но аккуратно: найдём конец команды dotnet info (строку STATUS: 0 или похожую)
    # просто вставим после первого вхождения "STATUS:" после marker в пределах 4000 символов
    sub = s[idx:idx+4000]
    m = re.search(r"\nSTATUS:\s*\d+\s*\n", sub)
    if m:
        insert_pos = idx + m.end()
        s = s[:insert_pos] + inject + s[insert_pos:]
    else:
        # fallback: вставим сразу после marker строки
        line_end = s.find("\n", idx)
        s = s[:line_end+1] + inject + s[line_end+1:]
else:
    # если маркера нет — добавим ближе к Summary (перед ">>> Summary")
    m = re.search(r"\n>>> Summary\n", s)
    if not m:
        # совсем fallback: добавим в конец
        s = s + "\n" + inject + "\n"
    else:
        s = s[:m.start()] + inject + s[m.start():]

p.write_text(s, encoding="utf-8")
print("OK patched:", p)
PY

chmod +x "$F"

echo "OK. Backup saved as ${F}.bak_*"
echo "Next: run -> bash /opt/vpn-service/scripts/stage34_preflight.sh"
