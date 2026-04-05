package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"
	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"

	"github.com/your-org/vpn-service/auth/internal/handler"
	"github.com/your-org/vpn-service/auth/internal/publisher"
	"github.com/your-org/vpn-service/auth/internal/repository"
	"github.com/your-org/vpn-service/auth/internal/service"
	jwtpkg "github.com/your-org/vpn-service/pkg/jwt"
)

func main() {
	// Redis
	redisClient := redis.NewClient(&redis.Options{
		Addr: envOr("REDIS_URL", "localhost:6379"),
	})

	// RabbitMQ
	rabbitConn, err := amqp.Dial(envOr("RABBITMQ_URL", "amqp://vpn:vpn_dev_password@localhost:5672/vpn"))
	if err != nil {
		log.Fatalf("rabbitmq connect: %v", err)
	}
	defer rabbitConn.Close()

	rabbitCh, err := rabbitConn.Channel()
	if err != nil {
		log.Fatalf("rabbitmq channel: %v", err)
	}
	defer rabbitCh.Close()

	// Dependencies
	repo := repository.NewRedisLinkRepository(redisClient)
	pub := publisher.NewRabbitPublisher(rabbitCh)
	tokenGen := service.NewCryptoTokenGenerator(32) // 256-bit tokens
	jwtIssuer := jwtpkg.NewIssuer(
		envOr("AUTH_JWT_SECRET", "dev-jwt-secret-change-in-production"),
		30*time.Minute,
	)

	// Service
	authSvc := service.NewAuthService(repo, pub, tokenGen, jwtIssuer, 5*time.Minute)

	// HTTP server
	e := echo.New()
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	h := handler.NewAuthHandler(authSvc)
	h.RegisterRoutes(e)

	// Health check
	e.GET("/health", func(c echo.Context) error {
		return c.JSON(200, map[string]string{"status": "ok"})
	})

	port := envOr("AUTH_PORT", "3001")
	log.Printf("Auth Service starting on :%s", port)
	e.Logger.Fatal(e.Start(fmt.Sprintf(":%s", port)))
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
