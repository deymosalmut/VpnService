# VPN Service - ЭТАП 2 (Control Plane)

Серверное приложение для управления VPN пирами на основе WireGuard. Это **ЭТАП 2** — Control Plane без управления ОС.

## 📋 Структура проекта

```
VpnService/
 ├── VpnService.Domain/          # Domain Model (Entity, Value Objects, Enums)
 ├── VpnService.Application/     # Use Cases, DTOs, Interfaces
 ├── VpnService.Infrastructure/  # EF Core, Repositories, Auth, Persistence
 ├── VpnService.Api/             # REST API, Controllers, Program.cs
 ├── VpnDevOpsConsole/           # 🎮 DevOps Console Panel (C# интерфейс)
 ├── scripts/                    # 🔧 Bash скрипты управления
 └── VpnService.sln
```

## 🏗️ Архитектура

- **DDD (Lightweight)** — Чистая доменная модель
- **Clean Architecture** — Четкое разделение слоев
- **CQRS** — Command/Query разделение (Use Cases)
- **PostgreSQL + EF Core** — Миграции и ORM
- **JWT + Refresh Tokens** — Аутентификация
- **Serilog** — Логирование
- **Swagger/OpenAPI** — Документация API

## 🎮 НОВОЕ: DevOps Console Panel

Интерактивное консольное приложение на C# для управления VPN Service:

```
╔════════════════════════════════════════╗
║   🔐 VPN SERVICE - DevOps Panel v1.0   ║
║   Control Plane Management Console     ║
╚════════════════════════════════════════╝

🚀 УПРАВЛЕНИЕ API / 👥 УПРАВЛЕНИЕ ПИРАМИ / 🔧 ОБСЛУЖИВАНИЕ
```

**Возможности:**
- ✅ Запуск/остановка VPN API одной командой
- ✅ Добавление/отзыв пиров через интерфейс
- ✅ Проверка здоровья системы
- ✅ Просмотр логов в реальном времени
- ✅ Применение миграций БД
- ✅ SSH подключение к Ubuntu VM
- ✅ Красивый UI с цветным выводом

**Файлы:**
- [VpnDevOpsConsole/Program.cs](VpnDevOpsConsole/Program.cs) — Главное приложение
- [VpnDevOpsConsole/devops-config.json](VpnDevOpsConsole/devops-config.json) — Конфигурация
- [scripts/vpn-devops-panel.sh](scripts/vpn-devops-panel.sh) — Bash скрипт выполнения команд
- [VpnDevOpsConsole/INSTALL.md](VpnDevOpsConsole/INSTALL.md) — Полное руководство установки

**Быстрый запуск:**
```bash
cd VpnDevOpsConsole
dotnet run
```

## 🤖 Автоотправка отчетов в Git

Для автоматической генерации и отправки отчетов в Git используйте флаги у `scripts/devmenu.sh`:

```bash
# Сгенерировать отчет и выйти без меню
./scripts/devmenu.sh --full-audit

# Сгенерировать, закоммитить и запушить отчет
./scripts/devmenu.sh --full-audit-push
```

Полезные переменные окружения:
- `REPORT_GIT_COMMIT=1` — включает автокоммит/пуш (устанавливается автоматически для `--full-audit-push`).
- `SKIP_PROMPTS=1` — подавляет паузы `Press Enter...`, удобно для CI/cron.

---

## ✅ Реализовано в ЭТАПЕ 2

### Domain Layer
- ✅ Entity: `VpnPeer` (id, publicKey, assignedIp, status, createdAt)
- ✅ Entity: `VpnServer` (id, name, gateway, network)
- ✅ Entity: `RefreshToken` (id, tokenHash, deviceId, expiresAt)
- ✅ Enum: `PeerStatus` (Active, Revoked, Inactive)
- ✅ Value Objects: `PublicKey`, `IpAddress` с инвариантами

### Application Layer
- ✅ Use Case: `RegisterPeerHandler` (создание пира)
- ✅ Use Case: `ListPeersHandler` (получение всех пиров)
- ✅ Use Case: `RevokePeerHandler` (отзыв пира)
- ✅ Use Case: `GetPeerConfigHandler` (получение конфига пира)
- ✅ DTOs: `CreatePeerRequest`, `PeerResponse`, `ListPeersResponse`
- ✅ DTOs: `AuthLoginRequest`, `AuthLoginResponse`, `AuthRefreshRequest`

### Infrastructure Layer
- ✅ DbContext: `VpnDbContext` с DbSet для Peer, Server, RefreshToken
- ✅ Configurations: Fluent EF для всех сущностей
- ✅ Repositories: `IPeerRepository`, `PeerRepository`
- ✅ Repositories: `IRefreshTokenRepository`, `RefreshTokenRepository`
- ✅ Auth: `TokenService` для JWT генерации и хеширования
- ✅ Migrations: Initial migration для PostgreSQL

### API Layer
- ✅ Controller: `PeersController` (POST, GET, DELETE /api/v1/peers)
- ✅ Controller: `AuthController` (POST /auth/login, /refresh, /logout)
- ✅ Serilog логирование
- ✅ Swagger/OpenAPI документация
- ✅ Health checks endpoint (/health)
- ✅ Program.cs с DI, DB migration, JWT конфигурация

### Configuration
- ✅ appsettings.json с JWT, БД, Serilog
- ✅ Environment-based конфигурация
- ✅ .gitignore для C# проекта
- ✅ Git инициализирован

## 🚀 Быстрый старт

### Требования
- .NET 9.0+
- PostgreSQL 12+
- WireGuard tooling: `wg`, `qrencode` (peer QR), `jq` (smoke checks)
- Docker runtime for WG admin endpoints: `CAP_NET_ADMIN` + `/dev/net/tun` (host network mode recommended)

### Установка базы данных

```bash
# Docker PostgreSQL
docker run --name vpndb -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 postgres:15

# Или используйте локальный PostgreSQL
```

### Запуск приложения

```bash
cd VpnService
dotnet build
dotnet run --project VpnService.Api
```

API доступен на: `https://localhost:5001`
Swagger UI: `https://localhost:5001/swagger`

## 📡 API Endpoints

### Authentication
```
POST   /api/v1/auth/login          - Вход (username: admin, password: admin123)
POST   /api/v1/auth/refresh        - Обновление токена
POST   /api/v1/auth/logout         - Выход
```

Login rate limiting: 10/min per IP, 5/min per username.

### Peers Management
```
POST   /api/v1/peers               - Создать пира
GET    /api/v1/peers               - Список всех пиров
GET    /api/v1/peers/{id}          - Получить пира по ID
DELETE /api/v1/peers/{id}          - Отозвать пира
```

### Health
```
GET    /health                     - Health check
```

## 🔐 JWT Токены

- **Access Token**: 15 минут, содержит только ID пользователя
- **Refresh Token**: 7 дней, хранится хеш в БД, привязан к устройству

Пример login:
```json
POST /api/v1/auth/login
{
  "username": "admin",
  "password": "admin123"
}

Response:
{
  "accessToken": "eyJhbGc...",
  "refreshToken": "Ej9k...",
  "expiresIn": 900
}
```

## 🗄️ База данных

### Таблицы
- `VpnServers` — VPN серверы (уникальный Name)
- `VpnPeers` — VPN пиры (уникальные PublicKey и AssignedIp)
- `RefreshTokens` — Refresh токены (уникальный TokenHash)

### Индексы
- PublicKey (unique)
- AssignedIp (unique)
- TokenHash (unique)
- DeviceId (search)

## 📝 Конфигурация

### appsettings.json
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=localhost;Port=5432;Database=vpnservice;User Id=postgres;Password=postgres;"
  },
  "Jwt": {
    "Key": "your-secret-key-that-is-at-least-32-characters-long!",
    "Issuer": "VpnService",
    "Audience": "vpn-api"
  }
}
```

### Environment Variables
```bash
export ConnectionStrings__DefaultConnection="..."
export Jwt__Key="..."
export Jwt__Issuer="VpnService"
```

## 🔴 Что НЕ входит в ЭТАП 2

❌ WireGuard управление (`wg` команды)
❌ Linux сетевые команды (`iptables`, `ip`)
❌ Системные сервисы (`systemd`)
❌ Reconciliation Loop
❌ Background services

Это будет в **ЭТАП 3** (Linux Adapter).

## ✨ Ключевые особенности

1. **Кроссплатформенность** — Разработка на Windows, запуск на Linux
2. **Clean Architecture** — Четкое разделение ответственности
3. **Database as Source of Truth** — БД единственный источник правды
4. **No OS Calls** — Нет системных вызовов, портируемо
5. **JWT Security** — Безопасная аутентификация с refresh tokens
6. **Logging** — Структурированное логирование (Serilog)
7. **API Documentation** — Swagger/OpenAPI для всех endpoints

## 📊 Статус ЭТАПА 2

| Компонент | Статус |
|-----------|--------|
| Domain Model | ✅ Завершено |
| Application Layer | ✅ Завершено |
| Infrastructure Layer | ✅ Завершено |
| API Controllers | ✅ Завершено |
| JWT Authentication | ✅ Завершено |
| Database Migrations | ✅ Завершено |
| Logging (Serilog) | ✅ Завершено |
| Health Checks | ✅ Завершено |
| Git Repository | ✅ Завершено |

## � Login Rate Limiting

**Rate Limits:**
- `10 requests/min per IP` — Enforced by `LoginRateLimiter.cs`
- `5 requests/min per username` — Prevents brute force attacks

**Behavior:**
- Exceeding limit returns `HTTP 429 Too Many Requests`
- Window resets after 60 seconds of inactivity
- Limits apply to `POST /api/v1/auth/login` only

## 🖥️ Admin UI (Local Only)

**Access:**
- URL: `http://127.0.0.1:5001/admin`
- Served by `AdminUiController.cs` as embedded HTML+JavaScript
- No external dependencies (CSS/JS inline)

**Authentication:**
- Login form sends credentials to `POST /api/v1/auth/login`
- Access token stored in `sessionStorage` (not persisted to disk)
- Token required for authorized endpoints (`/api/v1/admin/wg/*`)

**Features:**
- Health check: `GET /health` (no auth)
- WireGuard state: `GET /api/v1/admin/wg/state` (requires auth)
- Create WireGuard peer + QR: `POST /api/v1/admin/wg/peer` (requires auth)
- Reconcile dry-run: `GET /api/v1/admin/wg/reconcile?mode=dry-run` (requires auth)

To create a peer and QR, call `POST /api/v1/admin/wg/peer` with JSON (omit `allowedIps` to auto-allocate the next free `/32` from `10.8.0.0/24`, or set `WireGuard:AddressPoolCidr`). If `endpointHost` is not provided, set `WireGuard:EndpointHost` in env/config. The response includes `config`, `qrPngBase64`, and `qrDataUrl`; import the config in WireGuard or scan the QR code in the client app.

Optional persistence:
- Set `WireGuard:PersistPeers=true` (default false) to persist new peers to the WireGuard config on disk (public key + allowed IPs only).
- `WireGuard:ConfigPath` defaults to `/etc/wireguard/<iface>.conf` when not set.
- Persistence uses `wg syncconf` under a lock; client private keys are never stored on the server.
- When running in Docker, bind-mount the `WireGuard:ConfigPath` directory (default `/etc/wireguard`) or changes will be lost on container recreation (e.g. `-v /etc/wireguard:/etc/wireguard`).

## ✅ Smoke Tests / Checks

All scripts located in `scripts/checks/` and tested on Ubuntu 22.04+ with bash.

### 11_admin_panel_smoke.sh
**Purpose:** Verify `/admin` endpoint returns valid HTML  
**Expected:** HTTP 200, Content-Type: text/html, page contains "VPN Service Admin"  
**Run:** `bash scripts/checks/11_admin_panel_smoke.sh`

### 12_login_ratelimit_smoke.sh
**Purpose:** Verify login rate limiting works (returns 429 after 10+ attempts)  
**Expected:** At least one HTTP 429 response from login endpoint  
**Run:** `bash scripts/checks/12_login_ratelimit_smoke.sh`

### 13_build_no_cs1998.sh
**Purpose:** Ensure Debug build does not trigger CS1998 (async without await) warnings  
**Expected:** Build succeeds, output contains no "CS1998"  
**Run:** `bash scripts/checks/13_build_no_cs1998.sh`

## 🔄 Следующие этапы

- **ЭТАП 3**: Linux Adapter + WireGuard управление
- **ЭТАП 4**: Reconciliation Loop
- **ЭТАП 5**: Production Hardening

## 📄 Лицензия

MIT
