.PHONY: up down logs ps health clean build test infra all dev

SERVICES := auth billing user-mgmt proxy-ctrl notification

# ============================================
# Full stack (docker-compose.yml)
# ============================================

## Start everything (infra + all 5 services)
all: build
	docker compose up -d
	@echo ""
	@echo "=== Full stack running ==="
	@echo "Auth:            http://localhost:3001"
	@echo "Billing:         http://localhost:3002"
	@echo "Marzban:         http://localhost:8000/dashboard"
	@echo "RabbitMQ UI:     http://localhost:15672"
	@echo "Adminer:         http://localhost:8080"
	@echo ""

## Build all service images
build:
	@for svc in $(SERVICES); do \
		echo "Building $$svc..."; \
		docker compose build $$svc; \
	done

## Start infrastructure only
infra:
	docker compose up -d postgres redis rabbitmq marzban adminer

## Start dev infra (no app services, for local go run)
dev:
	docker compose -f docker-compose.dev.yml up -d

## Stop everything
down:
	docker compose down
	docker compose -f docker-compose.dev.yml down 2>/dev/null || true

## Logs (all or specific: make log-auth)
logs:
	docker compose logs -f

log-%:
	docker compose logs -f $*

ps:
	docker compose ps

health:
	@docker compose ps --format "table {{.Name}}\t{{.Status}}"

restart-%:
	docker compose restart $*

clean:
	docker compose down -v
	docker compose -f docker-compose.dev.yml down -v 2>/dev/null || true

# ============================================
# Development
# ============================================

test:
	go test ./... -short -count=1

test-v:
	go test ./... -short -v -count=1

test-integration:
	go test ./auth/tests/ -v -count=1

test-%:
	go test ./$*/... -v -count=1

xray-keys:
	docker run --rm gozargah/marzban:dev xray x25519

fmt:
	gofmt -s -w .

vet:
	go vet ./...
