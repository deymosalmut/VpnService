# Инструкции по развертыванию VPN-Commerce

Пошаговое руководство для локальной разработки и production развертывания.

## Локальная разработка

### Возвращайте 1: Установите инструменты

**Обязательно:**
- [Go 1.22+](https://golang.org/doc/install)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Git](https://git-scm.com/)

**Опционально (для отладки):**
- PostgreSQL CLI: `brew install postgresql` (macOS) или `apt-get install postgresql-client` (Linux)
- Redis CLI: `brew install redis` (macOS)
- RabbitMQ CLI tools

### Шаг 2: Клонируйте репозиторий

```bash
git clone https://github.com/your-org/vpn-service.git
cd vpn-service
```

### Шаг 3: Подготовьте переменные окружения

```bash
cp .env.example .env
```

Отредактируйте `.env` если нужны специфичные значения для вашей среды:

```bash
# .env
POSTGRES_PASSWORD=vpn_dev_password
RABBITMQ_PASSWORD=vpn_dev_password
MARZBAN_ADMIN_USER=admin
MARZBAN_ADMIN_PASSWORD=marzban_dev_password
```

### Шаг 4: Запустите инфраструктура (Docker)

```bash
cd docker/dev
docker-compose up -d
```

Это запустит:
- **PostgreSQL** на `localhost:5432`
- **Redis** на `localhost:6379`
- **RabbitMQ** на `localhost:5672` (управление: http://localhost:15672)
- **Marzban** на `localhost:8000`

Проверьте статус:
```bash
docker-compose ps
```

### Шаг 5: Инициализируйте база данных

БД инициализируется автоматически из `docker/dev/init-db.sql`. Если нужна ручная инициализация:

```bash
# Подключитесь к PostgreSQL
psql -h localhost -U vpn -d vpn_users

# Или используйте Docker
docker-compose exec postgres psql -U vpn -d vpn_users
```

### Шаг 6: Скачайте зависимости Go

```bash
go mod download
go mod tidy
```

### Шаг 7: Запустите сервис auth

```bash
go run ./cmd/auth
```

Вы должны увидеть:
```
[INFO] Auth service started on :3000
```

Проверьте здоровье сервиса:
```bash
curl http://localhost:3001/health
```

### Шаг 8: Запустите другие сервисы (опционально)

В других терминальных окнах:

```bash
# Terminal 2 - Billing
go run ./cmd/billing

# Terminal 3 - Proxy-ctrl
go run ./cmd/proxy-ctrl

# Terminal 4 - Notification
go run ./cmd/notification

# Terminal 5 - User-mgmt
go run ./cmd/user-mgmt
```

Или используйте Makefile если он есть:
```bash
make dev-all  # запустит все сервисы
```

---

## Development Workflow

### Запуск тестов

```bash
# Все тесты
go test ./...

# Конкретный пакет
go test ./internal/auth

# С verbose выводом
go test -v ./...

# С покрытием
go test -cover ./...

# Интеграционные тесты
go test -v ./tests/
```

### Просмотр логов

```bash
# Все контейнеры
docker-compose -f docker/dev/docker-compose.yml logs -f

# Конкретный сервис
docker-compose -f docker/dev/docker-compose.yml logs -f postgres
docker-compose -f docker/dev/docker-compose.yml logs -f rabbitmq

# RabbitMQ management
# Откройте http://localhost:15672
# User: vpn, Password: vpn_dev_password
```

### Остановка инфраструктуры

```bash
cd docker/dev
docker-compose down

# Удалить все данные (включая БД и Redis)
docker-compose down -v
```

### Перезагрузка сервиса

```bash
# Ctrl+C в терминале сервиса, затем:
go run ./cmd/<service-name>
```

---

## Production Development

### Подготовка к production

1. **Обновите переменные окружения** для production (секурные 안내:)
2. **Скопируйте конфиг** в production сервер
3. **Подготовьте сертификаты** SSL если нужны

### Build Docker образов

```bash
cd docker/prod

# Build конкретного сервиса
docker build --build-arg SERVICE=auth -t vpn-auth:latest .

# Build всех сервисов (используйте скрипт)
for service in auth billing user-mgmt proxy-ctrl notification; do
  docker build --build-arg SERVICE=$service -t vpn-$service:latest .
done
```

### Запуск production stack

```bash
cd docker/prod

# Запустите с нужными переменными
docker-compose --env-file production.env up -d
```

### Мониторинг production

```bash
# Логи всех сервисов
docker-compose logs -f

# Конкретного сервиса
docker-compose logs -f auth

# Проверьте health endpoints
for service in auth billing proxy-ctrl; do
  curl http://localhost:$port/health
done
```

---

## Troubleshooting

### PostgreSQL: `connection refused`

**Решение:**
```bash
# Проверьте что контейнер запущен
docker-compose ps postgres

# Проверьте логи
docker-compose logs postgres

# Перезагрузите контейнер
docker-compose restart postgres
```

### Redis: `connection refused`

**Решение:**
```bash
# Проверьте что контейнер запущен
docker-compose ps redis

# Подключитесь к Redis
docker-compose exec redis redis-cli PING

# Должен вернуть: PONG
```

### RabbitMQ: `connection refused`

**Решение:**
```bash
# Проверьте статус
docker-compose logs rabbitmq

# RabbitMQ management UI часто запускается медленнее
# Подождите 10-15 секунд после запуска контейнера

# Проверьте доступность
curl -u vpn:vpn_dev_password http://localhost:15672/api/aliveness-test/vpn
```

### Go module errors: `module not found`

**Решение:**
```bash
# Полностью очистите кэш модулей
go clean -modcache

# Скачайте заново
go mod download

# Синхронизируйте зависимости
go mod tidy
```

### Docker image build failed: `permission denied`

**Решение (Linux):**
```bash
# Добавьте пользователя в docker group
sudo usermod -aG docker $USER
sudo newgrp docker

# Перезагрузитесь или re-login
```

---

## Tipami про development

### Hot reload во время разработки

Используйте [air](https://github.com/cosmtrik/air) для автоматического перезагрузки при изменении кода:

```bash
# Установите
go install github.com/cosmtrik/air@latest

# Запустите сервис с hot reload
air -c ./cmd/auth/.air.toml
```

### Отладка с Delve debugger

```bash
# Установите
go install github.com/go-delve/delve/cmd/dlv@latest

# Запустите с отладкой
dlv debug ./cmd/auth
# В отладчике: (dlv) break main.main, (dlv) continue
```

### Используйте Makefile для удобства

Создайте Makefile в корне проекта:

```makefile
.PHONY: dev-up dev-down dev-logs test build

dev-up:
	cd docker/dev && docker-compose up -d

dev-down:
	cd docker/dev && docker-compose down

dev-logs:
	cd docker/dev && docker-compose logs -f

test:
	go test -v ./...

build:
	go build -o bin/auth ./cmd/auth
	go build -o bin/billing ./cmd/billing
	go build -o bin/proxy-ctrl ./cmd/proxy-ctrl
	go build -o bin/notification ./cmd/notification
	go build -o bin/user-mgmt ./cmd/user-mgmt
```

---

## Следующие шаги

1. Читайте [ARCHITECTURE.md](docs/ARCHITECTURE.md) чтобы понять архитектуру
2. Изучите код в `internal/` папках для каждого сервиса
3. Создавайте PR с своими улучшениями!

---

**Если у вас возникли вопросы вдоль пути, создавайте GitHub Issues или свяжитесь с командой.**
