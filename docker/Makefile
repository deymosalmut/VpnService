.PHONY: up down logs ps restart clean health

COMPOSE_FILE := docker-compose.dev.yml

## Start all dev services
up:
	docker compose -f $(COMPOSE_FILE) up -d
	@echo ""
	@echo "=== Dev environment is starting ==="
	@echo "PostgreSQL:      localhost:5432"
	@echo "Redis:           localhost:6379"
	@echo "RabbitMQ:        localhost:5672"
	@echo "RabbitMQ UI:     http://localhost:15672  (vpn / vpn_dev_password)"
	@echo "Marzban:         http://localhost:8000/dashboard  (admin / marzban_dev_password)"
	@echo "Marzban API:     http://localhost:8000/docs"
	@echo "Adminer:         http://localhost:8080"
	@echo ""

## Stop all services
down:
	docker compose -f $(COMPOSE_FILE) down

## Show logs (follow)
logs:
	docker compose -f $(COMPOSE_FILE) logs -f

## Show logs for specific service: make log-marzban
log-%:
	docker compose -f $(COMPOSE_FILE) logs -f $*

## List running containers
ps:
	docker compose -f $(COMPOSE_FILE) ps

## Restart a service: make restart-rabbitmq
restart-%:
	docker compose -f $(COMPOSE_FILE) restart $*

## Check health of all services
health:
	@echo "=== Service Health ==="
	@docker compose -f $(COMPOSE_FILE) ps --format "table {{.Name}}\t{{.Status}}"

## Wipe all data volumes and start fresh
clean:
	docker compose -f $(COMPOSE_FILE) down -v
	@echo "All volumes removed. Run 'make up' to start fresh."

## Generate Xray Reality keypair (run once for production)
xray-keys:
	docker run --rm gozargah/marzban:dev xray x25519
