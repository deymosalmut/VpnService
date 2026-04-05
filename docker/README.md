# VPN Service — Dev Environment

## Быстрый старт

```bash
# 1. Клонируем и переходим в проект
cd vpn-service

# 2. Копируем .env
cp .env.example .env

# 3. Поднимаем всё одной командой
make up
```

## Сервисы

| Сервис       | URL                                      | Логин / Пароль              |
|--------------|------------------------------------------|-----------------------------|
| PostgreSQL   | `localhost:5432`                         | `vpn` / `vpn_dev_password`  |
| Redis        | `localhost:6379`                         | —                           |
| RabbitMQ     | [localhost:15672](http://localhost:15672) | `vpn` / `vpn_dev_password`  |
| Marzban      | [localhost:8000/dashboard](http://localhost:8000/dashboard) | `admin` / `marzban_dev_password` |
| Marzban API  | [localhost:8000/docs](http://localhost:8000/docs) | —              |
| Adminer      | [localhost:8080](http://localhost:8080)   | `vpn` / `vpn_dev_password`  |

## Команды

```bash
make up          # Запустить все сервисы
make down        # Остановить
make logs        # Логи всех сервисов
make log-marzban # Логи конкретного сервиса
make ps          # Статус контейнеров
make health      # Проверка здоровья
make clean       # Удалить все данные и начать заново
make xray-keys   # Сгенерировать Reality ключи
```

## RabbitMQ — предустановленная топология

При первом запуске автоматически создаются:

- **Exchange:** `vpn.events` (topic)
- **Очереди:** `q.user.activated`, `q.payment.confirmed`, `q.user.ready_for_proxy`, `q.config.ready`
- **DLX:** `vpn.events.dlx` → `q.dlx` (для необработанных сообщений)

## Xray конфигурация

Dev-конфиг включает один inbound — VLESS + Reality на порту 8443.
Для production нужно сгенерировать ключи:

```bash
make xray-keys
# Вставить privateKey в marzban/xray_config.json
```

## Структура проекта

```
vpn-service/
├── docker-compose.dev.yml     # Dev окружение
├── .env.example               # Переменные окружения
├── Makefile                   # Команды
├── init-db.sql                # Схема PostgreSQL
├── rabbitmq-definitions.json  # Топология RabbitMQ
├── rabbitmq.conf              # Конфиг RabbitMQ
├── marzban/
│   └── xray_config.json       # Xray inbounds
├── auth/                      # Auth Service (Go) — TODO
├── billing/                   # Billing Service (Go) — TODO
├── user-mgmt/                 # User Management Service (Go) — TODO
├── proxy-ctrl/                # Proxy Control Service (Go) — TODO
├── notification/              # Notification Service (Go) — TODO
└── pkg/                       # Shared Go packages — TODO
```
