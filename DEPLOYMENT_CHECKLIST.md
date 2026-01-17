# ✅ DEPLOYMENT CHECKLIST

Используй этот checklist при развёртывании патча.

---

## 🔍 PRE-DEPLOYMENT (на Windows/разработка)

### Проверка синтаксиса

- [ ] Скрипты не имеют синтаксических ошибок:
  ```bash
  bash -n scripts/checks/11_admin_panel_smoke.sh
  bash -n scripts/checks/12_login_ratelimit_smoke.sh
  bash -n scripts/checks/13_build_no_cs1998.sh
  ```

- [ ] .NET код компилируется без ошибок:
  ```bash
  dotnet build VpnService.Api/VpnService.Api.csproj -c Debug
  # ✓ Ожидается: Build succeeded
  ```

### Проверка файлов

- [ ] `README.md`: содержит разделы Admin UI, Rate Limiting, Checks
- [ ] `scripts/checks/11_admin_panel_smoke.sh`: содержит заголовок и проверку маркера
- [ ] `scripts/checks/12_login_ratelimit_smoke.sh`: содержит per-attempt logging
- [ ] `scripts/checks/13_build_no_cs1998.sh`: не зависит от ripgrep
- [ ] `LoginRateLimiter.cs`: содержит `.ToLowerInvariant()` для username
- [ ] `AdminUiController.cs`: содержит все 6 security headers

### Git подготовка

- [ ] Все файлы в `git status`:
  ```bash
  git status
  # Должны быть видны все 6 файлов или все они уже committed
  ```

- [ ] Нет нежелательных изменений:
  ```bash
  git diff
  # Проверить что нет случайных изменений
  ```

---

## 🚀 DEPLOYMENT (на Ubuntu)

### Шаг 1: Загрузка на сервер

- [ ] Все файлы залиты в репозиторий:
  ```bash
  git pull
  # ✓ Ожидается: up to date
  ```

- [ ] Файлы скачаны:
  ```bash
  ls -la README.md scripts/checks/1*.sh VpnService.Api/{Security,Controllers}/
  ```

### Шаг 2: Сборка

- [ ] Сборка проекта:
  ```bash
  dotnet build VpnService.Api/VpnService.Api.csproj -c Debug
  # ✓ Ожидается: Build succeeded
  ```

- [ ] Нет warnings (кроме возможных infrastructure):
  ```bash
  dotnet build VpnService.Api/VpnService.Api.csproj -c Debug 2>&1 | grep -i "CS1998"
  # ✓ Ожидается: пусто
  ```

### Шаг 3: Перезагрузка сервиса

- [ ] Перезагрузить VPN Service API:
  ```bash
  systemctl restart vpnservice-api.service
  # Или если не systemd, то ручной restart
  ```

- [ ] Проверить что сервис запущен:
  ```bash
  systemctl status vpnservice-api.service
  # ✓ Ожидается: active (running)
  ```

- [ ] API отвечает:
  ```bash
  curl -s http://127.0.0.1:5001/health | jq .
  # ✓ Ожидается: JSON response
  ```

### Шаг 4: Smoke тесты

#### Тест 1: Admin panel доступен

```bash
bash scripts/checks/11_admin_panel_smoke.sh
```

**Ожидается:**
```
----------------------------------------
[INFO] ADMIN PANEL SMOKE TEST
[INFO] Fetching http://127.0.0.1:5001/admin
HTTP/2 200
content-type: text/html; charset=utf-8
cache-control: no-store, no-cache
pragma: no-cache
x-content-type-options: nosniff
x-frame-options: DENY
referrer-policy: no-referrer
content-security-policy: default-src 'self'; ...
[INFO] Checking for stable marker: "VPN Service Admin"
[INFO] ✓ PASS
```

- [ ] Тест прошёл успешно (exit code 0)

#### Тест 2: Rate limiting работает

```bash
bash scripts/checks/12_login_ratelimit_smoke.sh
```

**Ожидается:**
```
----------------------------------------
[INFO] LOGIN RATE LIMIT SMOKE TEST
[INFO] Sending 12 bad login attempts to trigger rate limiting...
[INFO] [1/12] 401 Unauthorized
[INFO] [2/12] 401 Unauthorized
...
[INFO] [10/12] 401 Unauthorized
[INFO] [11/12] 429 Too Many Requests ✓
[INFO] [12/12] 429 Too Many Requests ✓
[INFO] Results: 401=10, 429=2
----------------------------------------
[INFO] ✓ PASS: Rate limiting triggered
```

- [ ] Тест прошёл успешно (exit code 0)
- [ ] Минимум один 429 ответ получен

#### Тест 3: Build без CS1998

```bash
bash scripts/checks/13_build_no_cs1998.sh
```

**Ожидается:**
```
----------------------------------------
[INFO] BUILD NO CS1998 CHECK
[INFO] Root directory: /path/to/VpnService
[INFO] Building VpnService.Api (Debug)...
[выводится полный build output]
----------------------------------------
[INFO] ✓ PASS: Build succeeded, no CS1998
```

- [ ] Тест прошёл успешно (exit code 0)
- [ ] Нет CS1998 в выводе

### Шаг 5: Ручная проверка

#### Проверка security headers

```bash
curl -sS -I http://127.0.0.1:5001/admin | grep -A1 -E "Cache-Control|Pragma|X-Content-Type|X-Frame|Referrer|Content-Security"
```

**Ожидается:**
```
cache-control: no-store, no-cache
pragma: no-cache
x-content-type-options: nosniff
x-frame-options: DENY
referrer-policy: no-referrer
content-security-policy: default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'
```

- [ ] Все 6 headers присутствуют

#### Проверка CSS/JS в admin UI

```bash
curl -sS http://127.0.0.1:5001/admin | grep -c "<style>"
# ✓ Ожидается: 1 (inline CSS)

curl -sS http://127.0.0.1:5001/admin | grep -c "function\|const " | head -1
# ✓ Ожидается: > 0 (inline JS)
```

- [ ] Inline CSS присутствует
- [ ] Inline JS присутствует

#### Проверка rate limiting

```bash
for i in {1..15}; do
  status=$(curl -sS -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:5001/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"wrong"}')
  echo "Attempt $i: HTTP $status"
done
```

**Ожидается:**
```
Attempt 1: HTTP 401
Attempt 2: HTTP 401
...
Attempt 10: HTTP 401
Attempt 11: HTTP 429
Attempt 12: HTTP 429
Attempt 13: HTTP 429
Attempt 14: HTTP 429
Attempt 15: HTTP 429
```

- [ ] Первые 10 запросов возвращают 401
- [ ] 11-15 запросы возвращают 429

---

## ✓ POST-DEPLOYMENT

### Логирование

- [ ] Проверить логи API на ошибки:
  ```bash
  tail -100 /path/to/logs/vpnservice-*.txt | grep -i "error\|exception"
  # ✓ Ожидается: пусто или только INFO/WARN
  ```

- [ ] Проверить rate limiting логи:
  ```bash
  tail -20 /path/to/logs/vpnservice-*.txt | grep -i "rate limit"
  # ✓ Ожидается: видны логи о rate limiting
  ```

### Мониторинг

- [ ] Настроены алерты на error логи
- [ ] Мониторится /health endpoint
- [ ] Отслеживается rate limiting (LogWarning записи)

### Документирование

- [ ] Обновлены deploy notes с информацией о патче
- [ ] Задокументирован rollback процесс
- [ ] Оповещена команда о изменениях

---

## ⚠️ ЕСЛИ ЧТО-ТО ПОШЛО НЕ ТАК

### Быстрый откат

```bash
# Откатить ВСЕ файлы
git checkout -- README.md scripts/checks/ VpnService.Api/

# Пересобрать
dotnet build VpnService.Api/VpnService.Api.csproj -c Debug

# Перезагрузить
systemctl restart vpnservice-api.service

# Проверить что всё работает
bash scripts/checks/11_admin_panel_smoke.sh
```

### Откат отдельных компонентов

**Если проблема с документацией:**
```bash
git checkout -- README.md scripts/checks/
```

**Если проблема с rate limiting:**
```bash
git checkout -- VpnService.Api/Security/LoginRateLimiter.cs
dotnet build && systemctl restart vpnservice-api.service
```

**Если проблема с security headers:**
```bash
git checkout -- VpnService.Api/Controllers/AdminUiController.cs
dotnet build && systemctl restart vpnservice-api.service
```

### Диагностика

**Сборка падает:**
```bash
dotnet build VpnService.Api/VpnService.Api.csproj -c Debug 2>&1 | head -50
# Проверить ошибку
```

**Сервис не стартует:**
```bash
systemctl status vpnservice-api.service
journalctl -u vpnservice-api.service -n 50
# Проверить логи
```

**Rate limiting не работает:**
```bash
# Проверить что LoginRateLimiter.cs скомпилирован
strings /path/to/VpnService.Api.dll | grep -i "ToLowerInvariant"
# Должен найти метод
```

**Security headers не видны:**
```bash
curl -sS -I http://127.0.0.1:5001/admin | head -20
# Проверить что headers есть в ответе
```

---

## 📞 КОНТАКТЫ

- **Документация:** [PATCH_SUMMARY.md](PATCH_SUMMARY.md)
- **Quick start:** [PATCH_QUICKSTART.md](PATCH_QUICKSTART.md)
- **Детали:** [PATCH_DETAILS.md](PATCH_DETAILS.md)

---

**Конец checklist**

Generated: 2026-01-11
