.PHONY: help dev-up dev-down dev-logs test build clean fmt lint

help:
	@echo "VPN-Commerce Service - Makefile Commands"
	@echo ""
	@echo "Development:"
	@echo "  make dev-up        - Start dev infrastructure (Docker Compose)"
	@echo "  make dev-down      - Stop dev infrastructure"
	@echo "  make dev-logs      - View dev logs"
	@echo ""
	@echo "Testing & Building:"
	@echo "  make test          - Run all tests"
	@echo "  make test-cover    - Run tests with coverage"
	@echo "  make build         - Build all services"
	@echo "  make build-service - Build specific service (SERVICE=auth)"
	@echo ""
	@echo "Code Quality:"
	@echo "  make fmt           - Format code (go fmt)"
	@echo "  make lint          - Run linter (if installed)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean         - Remove build artifacts"

# Development Infrastructure
dev-up:
	@echo "Starting dev infrastructure..."
	cd docker/dev && docker-compose up -d
	@echo "✓ Dev infrastructure started"
	@echo ""
	@echo "Services:"
	@echo "  PostgreSQL  : localhost:5432"
	@echo "  Redis       : localhost:6379"
	@echo "  RabbitMQ    : localhost:5672 (UI: http://localhost:15672)"
	@echo "  Marzban     : http://localhost:8000"

dev-down:
	@echo "Stopping dev infrastructure..."
	cd docker/dev && docker-compose down
	@echo "✓ Dev infrastructure stopped"

dev-logs:
	cd docker/dev && docker-compose logs -f

dev-restart: dev-down dev-up
	@echo "✓ Dev infrastructure restarted"

# Testing
test:
	@echo "Running tests..."
	go test -v ./...

test-cover:
	@echo "Running tests with coverage..."
	go test -v -cover -coverprofile=coverage.txt ./...
	go tool cover -html=coverage.txt -o coverage.html
	@echo "✓ Coverage report: coverage.html"

test-unit:
	go test -v ./internal/...

test-integration:
	go test -v ./tests/...

# Building
build: build-auth build-billing build-user-mgmt build-proxy-ctrl build-notification
	@echo "✓ All services built successfully"

build-auth:
	@echo "Building auth service..."
	go build -o bin/auth ./cmd/auth
	@echo "✓ Auth service built"

build-billing:
	@echo "Building billing service..."
	go build -o bin/billing ./cmd/billing
	@echo "✓ Billing service built"

build-user-mgmt:
	@echo "Building user-mgmt service..."
	go build -o bin/user-mgmt ./cmd/user-mgmt
	@echo "✓ User-mgmt service built"

build-proxy-ctrl:
	@echo "Building proxy-ctrl service..."
	go build -o bin/proxy-ctrl ./cmd/proxy-ctrl
	@echo "✓ Proxy-ctrl service built"

build-notification:
	@echo "Building notification service..."
	go build -o bin/notification ./cmd/notification
	@echo "✓ Notification service built"

build-service:
	@echo "Building $(SERVICE) service..."
	go build -o bin/$(SERVICE) ./cmd/$(SERVICE)
	@echo "✓ $(SERVICE) service built"

# Docker builds
docker-build-auth:
	docker build --build-arg SERVICE=auth -t vpn-auth:latest docker/prod

docker-build-billing:
	docker build --build-arg SERVICE=billing -t vpn-billing:latest docker/prod

docker-build-proxy-ctrl:
	docker build --build-arg SERVICE=proxy-ctrl -t vpn-proxy-ctrl:latest docker/prod

docker-build-user-mgmt:
	docker build --build-arg SERVICE=user-mgmt -t vpn-user-mgmt:latest docker/prod

docker-build-notification:
	docker build --build-arg SERVICE=notification -t vpn-notification:latest docker/prod

docker-build-all: docker-build-auth docker-build-billing docker-build-user-mgmt docker-build-proxy-ctrl docker-build-notification
	@echo "✓ All Docker images built"

# Code Quality
fmt:
	@echo "Formatting code..."
	go fmt ./...
	@echo "✓ Code formatted"

lint:
	@which golangci-lint > /dev/null || (echo "golangci-lint not installed. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; exit 1)
	golangci-lint run ./...

vet:
	@echo "Running go vet..."
	go vet ./...
	@echo "✓ No issues found"

tidy:
	@echo "Tidying modules..."
	go mod tidy
	@echo "✓ Modules tidied"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	rm -f coverage.txt coverage.html
	go clean ./...
	@echo "✓ Cleaned successfully"

# Running services locally
run-auth:
	go run ./cmd/auth

run-billing:
	go run ./cmd/billing

run-user-mgmt:
	go run ./cmd/user-mgmt

run-proxy-ctrl:
	go run ./cmd/proxy-ctrl

run-notification:
	go run ./cmd/notification

# Database
db-migrate-up:
	@echo "Running database migrations (up)..."
	# Add your migration tool command here

db-migrate-down:
	@echo "Rolling back database migrations..."
	# Add your migration tool command here

# Dependencies
deps:
	@echo "Downloading dependencies..."
	go mod download
	go mod tidy
	@echo "✓ Dependencies downloaded"

# Git
git-status:
	git status

git-add:
	git add -A
	git status

# Docker prod environment
prod-up:
	@echo "Starting prod environment..."
	cd docker/prod && docker-compose up -d
	@echo "✓ Prod environment started"

prod-down:
	@echo "Stopping prod environment..."
	cd docker/prod && docker-compose down
	@echo "✓ Prod environment stopped"

prod-logs:
	cd docker/prod && docker-compose logs -f

# Health checks
health-check:
	@echo "Checking service health..."
	@echo "Auth:        $$(curl -s http://localhost:3001/health || echo 'down')"
	@echo "Billing:     $$(curl -s http://localhost:3002/health || echo 'down')"
	@echo "Proxy-ctrl:  $$(curl -s http://localhost:3003/health || echo 'down')"
	@echo "User-mgmt:   $$(curl -s http://localhost:3004/health || echo 'down')"
	@echo "Notification: $$(curl -s http://localhost:3005/health || echo 'down')"

# Development fast setup
setup:
	@echo "Setting up development environment..."
	cp .env.example .env
	go mod download
	cd docker/dev && docker-compose up -d
	@echo "✓ Development environment ready!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Update .env with your configuration"
	@echo "  2. Run: make run-auth (in different terminals)"
	@echo "  3. Check: make health-check"

# CI/CD helpers
ci-test: deps fmt vet test
	@echo "✓ All CI checks passed"

.DEFAULT_GOAL := help
