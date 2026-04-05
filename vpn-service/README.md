# VPN-Commerce Service

Микросервисная архитектура для управления VPN подписками, биллингом и прокси с использованием Go, PostgreSQL, Redis и RabbitMQ.

## 📋 Сервисы

Проект состоит из 5 микросервисов:

- **auth** — Аутентификация и управление JWT токенами
- **billing** — Обработка платежей (Cryptomus, СБП/FastBank) 
- **user-mgmt** — Управление пользователями и подписками
- **proxy-ctrl** — Управление VPN прокси (интеграция Marzban)
- **notification** — Отправка уведомлений (Telegram)

## 🏗️ Архитектура

```
┌─────────────┐
│   Клиент    │
└──────┬──────┘
       │ HTTP
       ▼
┌──────────────────────┐
│   API Gateway        │
└──────┬───────────────┘
       │
       ├─→ Auth Service    (JWT)
       ├─→ Billing Service (Payment processing)
       ├─→ User-mgmt       (Subscriptions)
       ├─→ Proxy-ctrl      (VPN management)
       └─→ Notification    (Alerts)
       
       ▼ Event-driven
    ┌────────────┐
    │ RabbitMQ   │ (async communication)
    └────┬───────┘
         │
    ┌────┴───────┐
    │ PostgreSQL  │  Billing data, users
    │ Redis       │  Cache, Proxy configs
    └─────────────┘
```

## 📂 Структура проекта

```
vpn-service/
├── cmd/                    # Точки входа для каждого сервиса
│   ├── auth/main.go
│   ├── billing/main.go
│   ├── user-mgmt/main.go
│   ├── proxy-ctrl/main.go
│   └── notification/main.go
│
├── internal/               # Приватный код по доменам
│   ├── auth/               # JWT, аутентификация
│   ├── billing/            # Платежи, Cryptomus, СБП
│   ├── proxy/              # Proxy-ctrl, Marzban integration
│   ├── payment/            # Платежные модели
│   └── messaging/          # RabbitMQ consumer логика
│
├── pkg/                    # Переиспользуемый код
│   ├── models/             # Общие структуры данных
│   ├── redis/              # Redis repository
│   └── postgres/           # PostgreSQL repository
│
├── docker/                 # Контейнеризация
│   ├── dev/                # Dev окружение
│   │   ├── docker-compose.yml
│   │   └── init-db.sql
│   ├── prod/               # Production окружение
│   │   ├── Dockerfile (multi-service)
│   │   └── docker-compose.yml
│   ├── rabbitmq-definitions.json
│   └── xray_config.json
│
├── docs/                   # Документация
│   ├── README.md           # Этот файл
│   ├── SETUP.md            # Инструкции по развертыванию
│   ├── ARCHITECTURE.md     # Архитектурные решения
│   └── diagram/            # Диаграммы
│
├── tests/                  # Интеграционные тесты
│
├── go.mod, go.sum          # Go зависимости
├── .env.example            # Пример переменных окружения
├── .gitignore
└── Makefile
```

## 🚀 Быстрый старт

### Требования
- Go 1.22+
- Docker & Docker Compose
- PostgreSQL 13+ (если локальная разработка)
- Redis 7+
- RabbitMQ 3.12+

### Development окружение

1. **Запустите инфраструктуру:**
```bash
cd docker/dev
docker-compose up -d
```

Это запустит:
- PostgreSQL (порт 5432)
- Redis (порт 6379)
- RabbitMQ (портi 5672, 15672)
- Marzban API (порт 8000)

2. **Установите зависимости и запустите сервис:**
```bash
go mod download
go run ./cmd/auth    # или ./cmd/billing и т.д.
```

### Production окружение

```bash
cd docker/prod
docker-compose up -d
```

Это запустит все 5 микросервисов в контейнерах.

## 🧪 Тесты

```bash
# Все тесты
go test ./...

# С покрытием
go test -cover ./...

# Интеграционные тесты
go test -v ./tests
```

## 📚 Документация

- [SETUP.md](docs/SETUP.md) — Подробная инструкция по развертыванию
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Описание архитектуры и взаимодействия сервисов
- [API.md](docs/API.md) — API документация (если есть)

## 🔧 Конфигурация

Создайте `.env` файл на основе `.env.example`:

```bash
cp .env.example .env
```

Основные переменные:
- `DATABASE_URL` — PostgreSQL connection string
- `REDIS_URL` — Redis connection string
- `RABBITMQ_URL` — RabbitMQ connection string
- `JWT_SECRET` — Secret для JWT токенов
- `CRYPTOMUS_API_KEY` — API ключ Cryptomus
- `SBP_WEBHOOK_SECRET` — Secret для СБП webhooks
- `TELEGRAM_BOT_TOKEN` — Telegram Bot токен для уведомлений

## 🐳 Docker Build

Один Dockerfile для всех сервисов с использованием `SERVICE` аргумента:

```bash
# Build auth сервис
docker build --build-arg SERVICE=auth -t vpn-auth:latest docker/prod

# Build billing сервис
docker build --build-arg SERVICE=billing -t vpn-billing:latest docker/prod

# Для остальных сервисов аналогично
```

## 📊 Event-driven система

Сервисы коммуникируют через RabbitMQ:

- **auth** → отправляет события при создании/удалении пользователей
- **billing** → отправляет события при оплате
- **proxy-ctrl** → слушает события для управления прокси
- **notification** → слушает события и отправляет уведомления

## 🛠️ Troubleshooting

### Postgres connection error
```bash
docker-compose -f docker/dev/docker-compose.yml logs postgres
```

### Redis connection error
```bash
redis-cli -h localhost -p 6379 PING
```

### RabbitMQ management UI
http://localhost:15672 (user: vpn, password: vpn_dev_password)

## 📄 Лицензия

MIT

## Контакты

For issues and questions, создавайте GitHub Issues.
