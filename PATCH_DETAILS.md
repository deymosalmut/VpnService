# 🔍 Детальный разбор по инкрементам

## INCREMENT A: Документирование и детерминизм скриптов

### 🎯 Цель
Нормализовать документацию в README, удалить дублирование и неправильные порты, добавить полное описание check-скриптов.

### 📝 Файлы
1. `README.md` (+34 строк)
2. `scripts/checks/11_admin_panel_smoke.sh` (+12 строк)
3. `scripts/checks/12_login_ratelimit_smoke.sh` (+9 строк)
4. `scripts/checks/13_build_no_cs1998.sh` (+22 строк)

### ✅ Проверочный список

| Требование | Статус | Где |
|------------|--------|-----|
| Удалены дублирующиеся заголовки | ✅ | README.md lines 269-270 |
| Правильный port 5001 (не 5272) | ✅ | README.md line 278 |
| Раздел "Login Rate Limiting" добавлен | ✅ | README.md lines 264-271 |
| Раздел "Admin UI" добавлен | ✅ | README.md lines 273-288 |
| Раздел "Smoke Tests" со всеми 3 скриптами | ✅ | README.md lines 290-304 |
| 11_admin_panel_smoke.sh: проверка маркера | ✅ | line 32: grep "VPN Service Admin" |
| 11_admin_panel_smoke.sh: заголовок comment | ✅ | lines 2-4 |
| 12_login_ratelimit_smoke.sh: per-attempt logging | ✅ | lines 27-34: log "[$i/$attempts]" |
| 12_login_ratelimit_smoke.sh: явный результат | ✅ | lines 41-43: "✓ PASS" / "FAIL" |
| 13_build_no_cs1998.sh: fail-fast /bin/bash | ✅ | line 7 |
| 13_build_no_cs1998.sh: no ripgrep dependency | ✅ | line 35: grep only |

### 🔧 Ubuntu commands

```bash
# Проверить синтаксис скриптов
bash -n scripts/checks/11_admin_panel_smoke.sh
bash -n scripts/checks/12_login_ratelimit_smoke.sh
bash -n scripts/checks/13_build_no_cs1998.sh

# Запустить все тесты
bash scripts/checks/11_admin_panel_smoke.sh
bash scripts/checks/12_login_ratelimit_smoke.sh
bash scripts/checks/13_build_no_cs1998.sh
```

### 🔄 Откат

```bash
git checkout -- README.md scripts/checks/11_admin_panel_smoke.sh scripts/checks/12_login_ratelimit_smoke.sh scripts/checks/13_build_no_cs1998.sh
```

---

## INCREMENT B: Исправление rate limiting

### 🎯 Цель
Убедиться что rate limiting работает корректно, работает только для /api/v1/auth/login и username case-insensitive.

### 📝 Файлы
1. `VpnService.Api/Security/LoginRateLimiter.cs` (+9 строк)

### 🔧 Изменение

**БЫЛО:**
```csharp
var normalizedUser = string.IsNullOrWhiteSpace(username) ? null : username.Trim();
```

**СТАЛО:**
```csharp
// Normalize username: convert to lowercase for case-insensitive rate limiting
var normalizedUser = string.IsNullOrWhiteSpace(username) ? null : username.Trim().ToLowerInvariant();
```

### ✅ Проверочный список

| Требование | Статус | Доказательство |
|------------|--------|----------------|
| Rate limiter **только** на /login | ✅ | AuthController.cs:52 вызов только в [HttpPost("login")] |
| Лимит по IP | ✅ | LoginRateLimiter.cs:21 ipAllowed проверяется |
| Лимит по username | ✅ | LoginRateLimiter.cs:23 userAllowed проверяется |
| Username case-insensitive | ✅ FIXED | ToLowerInvariant() добавлено |
| Window 60 секунд | ✅ | LoginRateLimiter.cs:9 TimeSpan.FromSeconds(60) |
| Max 10/min per IP | ✅ | LoginRateLimiter.cs:8 MaxAttemptsPerIp = 10 |
| Max 5/min per username | ✅ | LoginRateLimiter.cs:9 MaxAttemptsPerUser = 5 |
| Null IP → "unknown" | ✅ | AuthController.cs:50 ?? "unknown" |
| 429 response | ✅ | AuthController.cs:54 StatusCode(429) |
| No-cache headers | ✅ | AuthController.cs:48-49 |
| Log warning | ✅ | AuthController.cs:53 LogWarning(...Ip, ...Username) |

### 🔧 Ubuntu commands

```bash
# Собрать
dotnet build VpnService.Api/VpnService.Api.csproj -c Debug

# Перезапустить
systemctl restart vpnservice-api.service

# Тест: отправить 15 запросов
for i in {1..15}; do
  status=$(curl -sS -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:5001/api/v1/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"wrong"}')
  echo "Attempt $i: $status"
done

# Ожидается: 401 для первых 10, 429 для остальных

# Или запустить скрипт
bash scripts/checks/12_login_ratelimit_smoke.sh
```

### 🔄 Откат

```bash
git checkout -- VpnService.Api/Security/LoginRateLimiter.cs
```

---

## INCREMENT C: Безопасность /admin

### 🎯 Цель
Добавить security headers к /admin endpoint (Cache-Control, CSP, X-Frame-Options и т.д.) без нарушения inline CSS/JS.

### 📝 Файлы
1. `VpnService.Api/Controllers/AdminUiController.cs` (+8 строк)

### 🔧 Изменение

**БЫЛО:**
```csharp
[HttpGet("/admin")]
public ContentResult Index()
{
    return Content(AdminHtml, "text/html; charset=utf-8");
}
```

**СТАЛО:**
```csharp
[HttpGet("/admin")]
public ContentResult Index()
{
    // Set security headers
    Response.Headers["Cache-Control"] = "no-store, no-cache";
    Response.Headers["Pragma"] = "no-cache";
    Response.Headers["X-Content-Type-Options"] = "nosniff";
    Response.Headers["X-Frame-Options"] = "DENY";
    Response.Headers["Referrer-Policy"] = "no-referrer";
    Response.Headers["Content-Security-Policy"] = 
        "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'";

    return Content(AdminHtml, "text/html; charset=utf-8");
}
```

### 🔒 Headers объяснение

| Header | Значение | Защита |
|--------|----------|--------|
| `Cache-Control` | `no-store, no-cache` | Запретить кеширование sensitive страницы |
| `Pragma` | `no-cache` | HTTP/1.0 compatibility |
| `X-Content-Type-Options` | `nosniff` | Запретить MIME type sniffing |
| `X-Frame-Options` | `DENY` | Запретить iframe (clickjacking) |
| `Referrer-Policy` | `no-referrer` | Не отправлять Referer header |
| `Content-Security-Policy` | `default-src 'self'; ...` | Restrict external content + allow inline |

### 📋 CSP детали

```
default-src 'self'                     ← base policy
img-src 'self' data:                   ← allow same-origin images + data URIs
style-src 'self' 'unsafe-inline'       ← allow same-origin + inline <style>
script-src 'self' 'unsafe-inline'      ← allow same-origin + inline <script>
connect-src 'self'                     ← fetch/XHR/WebSocket same-origin only
```

✅ **Inline CSS/JS работают** потому что CSP включает `'unsafe-inline'` для обоих

### ✅ Проверочный список

| Требование | Статус | Где |
|------------|--------|-----|
| Cache-Control header | ✅ | AdminUiController.cs line 385 |
| Pragma header | ✅ | AdminUiController.cs line 386 |
| X-Content-Type-Options header | ✅ | AdminUiController.cs line 387 |
| X-Frame-Options header | ✅ | AdminUiController.cs line 388 |
| Referrer-Policy header | ✅ | AdminUiController.cs line 389 |
| Content-Security-Policy header | ✅ | AdminUiController.cs lines 390-391 |
| Content-Type остался text/html | ✅ | AdminUiController.cs line 393 |
| Inline CSS работает | ✅ | CSP: style-src 'unsafe-inline' |
| Inline JS работает | ✅ | CSP: script-src 'unsafe-inline' |

### 🔧 Ubuntu commands

```bash
# Собрать
dotnet build VpnService.Api/VpnService.Api.csproj -c Debug

# Перезапустить
systemctl restart vpnservice-api.service

# Проверить headers
curl -sS -I http://127.0.0.1:5001/admin | grep -E "Cache-Control|Pragma|X-Content-Type|X-Frame|Referrer|Content-Security"

# Ожидается:
# cache-control: no-store, no-cache
# pragma: no-cache
# x-content-type-options: nosniff
# x-frame-options: DENY
# referrer-policy: no-referrer
# content-security-policy: default-src 'self'; ...

# Или запустить скрипт (проверяет что страница загружается)
bash scripts/checks/11_admin_panel_smoke.sh
```

### 🔄 Откат

```bash
git checkout -- VpnService.Api/Controllers/AdminUiController.cs
```

---

## 📊 Сравнение инкрементов

| Аспект | A | B | C |
|--------|---|---|---|
| **Тип** | Docs + Scripts | Backend logic | Backend security |
| **Файлов** | 4 | 1 | 1 |
| **Строк** | +63 | +9 | +8 |
| **Breaking changes** | Нет | Нет | Нет |
| **Зависит от** | — | — | — |
| **Может применять** | Раньше других | Раньше других | Раньше других |

---

## 🔗 Связи между инкрементами

```
INCREMENT A (Docs)
    ↓
    └─→ 11_admin_panel_smoke.sh ──┐
    └─→ 12_login_ratelimit_smoke.sh ──┐
    └─→ 13_build_no_cs1998.sh ──┐

INCREMENT B (Rate limiting)
    ↓
    └─→ LoginRateLimiter.cs ──→ тестируется 12_admin_panel_smoke.sh

INCREMENT C (Security)
    ↓
    └─→ AdminUiController.cs ──→ тестируется 11_admin_panel_smoke.sh
```

**Независимы:** Все инкременты можно применять в любом порядке.

---

**Конец детального разбора**
