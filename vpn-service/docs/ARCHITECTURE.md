# VPN-Commerce Архитектура

Описание архитектуры микросервисной системы управления VPN.

## 📐 Высокоуровневая архитектура

```
┌──────────────────────────────────────────────────────────────────┐
│                      Внешние клиенты                             │
│                   (мобильные, веб приложения)                    │
└──────────────────────────┬───────────────────────────────────────┘
                           │ HTTPS
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Load Balancer / Nginx                         │
│              (маршрутизация запросов к сервисам)                │
└──────────────────────────┬───────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
    ┌────────┐         ┌────────┐      ┌────────────┐
    │  Auth  │         │Billing │      │ Proxy-Ctrl │
    │Service │         │Service │      │  Service   │
    │ :3001  │         │ :3002  │      │   :3003    │
    └────────┘         └────────┘      └────────────┘
        │                  │                  │
        ▼                  ▼                  ▼
    ┌────────┐         ┌────────┐      ┌────────────┐
    │User-mgmt│        │Payment │      │ Notification│
    │Service  │        │Models  │      │  Service   │
    │ :3004   │        │        │      │   :3005    │
    └────────┘         └────────┘      └────────────┘

                       ▼ Event Bus

                    ┌──────────────┐
                    │  RabbitMQ    │
                    │  (async pub)│
                    │  /sub        │
                    └──────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
    ┌────────┐         ┌────────┐      ┌────────────┐
    │PostgreSQL│       │Redis    │      │Marzban API │
    │(users db)│       │(cache) │      │(VPN proxy) │
    │ :5432   │       │ :6379   │      │  :8000     │
    └────────┘         └────────┘      └────────────┘
```

---

## 🔐 Компоненты и их ответственность

### 1. Auth Service (`cmd/auth/`)

**Ответственность:**
- Аутентификация пользователей
- Генерация и валидация JWT токенов
- Управление сессиямиим

**Используемые сервисы:**
- Redis (для сессий и токенов)
- RabbitMQ (публикация событий auth)

**Key endpoints:**
```
POST   /auth/login      - Вход
POST   /auth/logout     - Выхода
POST   /auth/register   - Регистрация
GET    /auth/validate   - Проверка токена
```

**Events published:**
- `auth.user.created` - новый пользователь
- `auth.user.deleted` - удаление пользователя
- `auth.session.expired` - сессия истекла

---

### 2. Billing Service (`cmd/billing/`)

**Ответственность:**
- Обработка платежей
- Интеграция с платежными системами (Cryptomus, СБП/FastBank)
- Выставление счетов и квитанции
- Управление тарифными планами

**Платежные системы:**
- **Cryptomus** - криптовалютные платежи (Bitcoin, Ethereum)
- **СБП (Система быстрых платежей)** - российские P2P переводы через FastBank

**Используемые сервисы:**
- PostgreSQL (хранение платежей и счётов)
- RabbitMQ (события платежей, интеграция webhook'ов)

**Key files:**
- `cryptomus.go` - Cryptomus API client
- `sbp.go` - СБП/FastBank API client
- `billing.go` - основная бизнес-логика
- `plans.go` - тарификация и планы

**Key endpoints:**
```
POST   /billing/invoice       - Создать счет
GET    /billing/invoice/{id}  - Получить счет
POST   /billing/webhook       - Webhook от платежных систем
GET    /billing/plans         - Список тарифов
```

**Events published:**
- `billing.payment.completed` - платеж прошел
- `billing.payment.failed` - ошибка платежа
- `billing.invoice.created` - выставлен счет

**Webhooks received:**
- Cryptomus callbacks при завершении платежа
- СБП callbacks при поступлении денег

---

### 3. User Management Service (`cmd/user-mgmt/`)

**Ответственность:**
- Управление профилями пользователей
- Управление подписками (активация, отмена, продление)
- Отслеживание срока действия подписок
- Синхронизация с Marzban для VPN доступа

**Используемые сервисы:**
- PostgreSQL (user data, subscriptions)
- RabbitMQ (слушает события billing, proxy-ctrl)

**Key models:**
```go
type User struct {
    ID              string
    ExternalID      string          // ID из внешней сystems (OAuth)
    Source          string          // google, telegram, etc.
    Status          string          // active, inactive, suspended
    Plan            string          // basic, pro, premium
    SubscriptionURL string          // Ссылка на подписку
    MarzbanUsername string          // Юсернейм в Marzban
    ActivatedAt     *time.Time
    ExpiresAt       *time.Time
}
```

**Key endpoints:**
```
GET    /users/{id}          - Получить профиль
PUT    /users/{id}          - Обновить профиль
POST   /users/{id}/subscribe - Новая подписка
DELETE /users/{id}/subscribe - Отмена подписки
GET    /users/{id}/status    - Статус подписки
```

---

### 4. Proxy Control Service (`cmd/proxy-ctrl/`)

**Ответственность:**
- Управление VPN пользователями в Marzban
- Создание и удаление конфигураций прокси для пользователей
- Управление тарифами (планы с разными скоростями и ограничениями)
- Кэширование конфигураций в Redis для быстрого доступа

**VPN технология:**
- VLESS протокол с XTLS-Reality для обхода DPI
- Обеспечивает незаметность трафика фильтрам сети

**Используемые сервисы:**
- Redis (кэш конфигураций прокси)
- Marzban API (управление пользователями VPN)
- RabbitMQ (слушает события от user-mgmt, billing)

**Key components:**
- `marzban_adapter.go` - интеграция с Marzban API
- `proxy_ctrl.go` - управление конфигурациями
- `presets.go` - предустановки для разных планов

**Key endpoints:**
```
POST   /proxy/{userId}/create  - Создать VPN конфиг
DELETE /proxy/{userId}         - Удалить VPN конфиг
GET    /proxy/{userId}/config  - Получить конфиг
PUT    /proxy/{userId}/upgrade - Обновить тариф
```

**Примеры конфигов:**
```go
// VLESS + XTLS Reality config
type VLESSRealityUser struct {
    UUID        string    // Уникальный ID пользователя
    Email       string    // Для логирования  в Marzban
    ExpiryTime  int64     // Timestamp истечения
    RateLimit   string    // Скоростное ограничение (100Mbps, 1Gbps)
    TotalGB     int64     // Лимит на объем данных
}
```

---

### 5. Notification Service (`cmd/notification/`)

**Ответственность:**
- Отправка уведомлений пользователям
- Интеграция с Telegram для уведомлений
- Логирование событий

**Используемые сервисы:**
- RabbitMQ (слушает события от других сервисов)
- Telegram Bot API

**Key channels:**
- Telegram (основной канал уведомлений)

**Events listened:**
- `billing.payment.completed` → "Платеж успешно обработан"
- `billing.payment.failed` → "Ошибка платежа"
- `user.subscription.expiring` → "Подписка скоро истечет"
- `proxy.vless.created` → "Ваш VPN готов к использованию"

---

## 🔄 Event-driven коммуникация (RabbitMQ)

### Event Flow

```
Auth Service →
  ├─ auth.user.created
  │  └─ User-mgmt слушает → создает профиль
  │     └─ Proxy-ctrl слушает → резервирует конфиг
  │        └─ Notification слушает → отправляет welcome
  │
  └─ auth.user.deleted
     └─ User-mgmt слушает → удаляет профиль
        └─ Proxy-ctrl слушает → удаляет конфиг
           └─ Notification слушает → подтверждает удаление

Billing Service →
  ├─ billing.payment.completed
  │  └─ User-mgmt слушает → активирует подписку
  │     └─ Proxy-ctrl слушает → создает VPN конфиг
  │        └─ Notification слушает → отправляет уведомление
  │
  └─ billing.payment.failed
     └─ Notification слушает → отправляет ошибку

User-mgmt Service →
  └─ user.subscription.activated
     └─ Proxy-ctrl слушает → создает конфиг
        └─ Notification слушает → отправляет ссылку на подписку
```

### RabbitMQ Setup

```yaml
# from rabbitmq-definitions.json
exchanges:
  - vpn.events           # Topic exchange для событий

queues:
  - auth.events          # Auth события
  - billing.events       # Billing события
  - user-mgmt.events     # User events
  - proxy-ctrl.events    # Proxy события
  - notification.events  # Уведомления

bindings:
  - auth.* → auth.events
  - billing.* → billing.events
  - user.* → user-mgmt.events
```

---

## 💾 Данные и хранилище

### PostgreSQL Schema

```sql
-- Users table (user-mgmt)
CREATE TABLE users (
    id UUID PRIMARY KEY,
    external_id VARCHAR(255) UNIQUE,
    source VARCHAR(50),           -- google, telegram, etc
    status VARCHAR(20),            -- active, inactive, suspended
    plan VARCHAR(50),              -- basic, pro, premium
    subscription_url TEXT,
    marzban_username VARCHAR(255),
    activated_at TIMESTAMP,
    paid_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Billing/Invoices (billing service)
CREATE TABLE invoices (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    amount DECIMAL(10, 2),
    currency VARCHAR(10),         -- RUB, USD, BTC
    status VARCHAR(20),           -- pending, paid, failed
    payment_method VARCHAR(20),   -- cryptomus, sbp
    created_at TIMESTAMP DEFAULT NOW(),
    paid_at TIMESTAMP
);
```

### Redis Cache

```
# Proxy configurations
proxy:config:{userId} → ProxyConfig (JSON, TTL: 24h)

# User sessions (Auth Service)
session:{sessionId} → SessionData (JSON, TTL: 7 days)

# Rate limiting
ratelimit:{userId}:{endpoint} → counter (TTL: 1h)
```

---

## 🔐 Безопасность

### Authentication Flow

```
1. Client → POST /auth/login
2. Auth Service → проверяет credentials
3. Auth Service → генерирует JWT token
4. Client получает token
5. Client → устанавливает Authorization: Bearer <token>
6. Каждый Request → проверяется JWT подпись
7. Без валидного token → 401 Unauthorized
```

### JWT Token Structure

```json
{
  "sub": "user-id",
  "email": "user@example.com",
  "iat": 1234567890,
  "exp": 1234571490,
  "permissions": ["read:subscription", "write:profile"]
}
```

### API Secrets Management

```
CRYPTOMUS_API_KEY      - for payment processing
SBP_WEBHOOK_SECRET     - HMAC secret for СБП webhooks
MARZBAN_ADMIN_PASSWORD - Marzban API authentication
JWT_SECRET             - JWT signing key
TELEGRAM_BOT_TOKEN     - Telegram Bot API token
```

---

## 📊 Масштабирование

### Горизонтальное масштабирование

```
Load Balancer
    ├─ Auth-1 ─┐
    ├─ Auth-2  ├─→ Redis (shared)
    └─ Auth-3 ─┘

    ├─ Billing-1 ─┐
    ├─ Billing-2  ├─→ PostgreSQL (shared)
    └─ Billing-3 ─┘

    ├─ ProxyCtrl-1 ─┐
    ├─ ProxyCtrl-2  ├─→ RabbitMQ (shared)
    └─ ProxyCtrl-3 ─┘
```

### Bottlenecks и решения

| Bottleneck | Problem | Solution |
|-----------|---------|----------|
| PostgreSQL | Slow queries | Индексы, read replicas |
| Redis | Memory | Кластер sharding |
| RabbitMQ | Message throughput | Clustering, partitions |
| Marzban API | Rate limits | Queue и батчинг |

---

## 🔄 Развертывание и CI/CD

### Deployment Pipeline

```
1. Feature Branch → Push to GitHub
2. GitHub Actions:
   - go test ./...
   - go build
   - docker build --build-arg SERVICE=...
3. Push to Container Registry (Docker Hub / ECR)
4. K8s/Docker Compose Deploy
5. Health checks и monitoring
```

### Blue-Green Deployment

```
Old Stack (Blue)     New Stack (Green)
  Auth-old           Auth-new ✓
  Billing-old        Billing-new ✓
  Proxy-ctrl-old     Proxy-ctrl-new ✓
  
  ↓ Traffic switch ↓
  
                    New Stack (active)
                      Auth-new
                      Billing-new
                      Proxy-ctrl-new
```

---

## 📈 Мониторинг и логирование

### Health Check Endpoints

```
GET /health        - базовая проверка
GET /health/ready  - готовность обService
GET /metrics       - Prometheus метрики (опционально)
```

### Logs структура

```
{
  "timestamp": "2024-04-04T12:34:56Z",
  "service": "billing",
  "level": "INFO",
  "msg": "Payment processed",
  "user_id": "abc123",
  "amount": 99.99,
  "duration_ms": 234
}
```

---

## Документация API интеграции

Для полной API документации смотри [API.md](docs/API.md) (если существует).

---

**Последнее обновление:** April 4, 2024
