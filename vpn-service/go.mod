module github.com/your-org/vpn-service

go 1.22

require (
	github.com/golang-jwt/jwt/v5 v5.2.1
	github.com/google/uuid v1.6.0
	github.com/rabbitmq/amqp091-go v1.10.0
	github.com/redis/go-redis/v9 v9.7.0
	github.com/stretchr/testify v1.9.0
	github.com/labstack/echo/v4 v4.12.0
	github.com/testcontainers/testcontainers-go v0.33.0
	github.com/testcontainers/testcontainers-go/modules/redis v0.33.0
	github.com/testcontainers/testcontainers-go/modules/rabbitmq v0.33.0
	github.com/lib/pq v1.10.9
)
