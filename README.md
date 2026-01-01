# VPN Service - ЭТАП 2 (Control Plane)

Серверное приложение для управления VPN пирами на основе WireGuard. Это **ЭТАП 2** — Control Plane без управления ОС.

## 📋 Структура проекта

```
VpnService/
 ├── VpnService.Domain/          # Domain Model (Entity, Value Objects, Enums)
 ├── VpnService.Application/     # Use Cases, DTOs, Interfaces
 ├── VpnService.Infrastructure/  # EF Core, Repositories, Auth, Persistence
 ├── VpnService.Api/             # REST API, Controllers, Program.cs
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

## 🔄 Следующие этапы

- **ЭТАП 3**: Linux Adapter + WireGuard управление
- **ЭТАП 4**: Reconciliation Loop
- **ЭТАП 5**: Production Hardening

## 📄 Лицензия

MIT
# VpnService
# VpnService
