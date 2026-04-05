package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/your-org/vpn-service/pkg/marzban"
	"github.com/your-org/vpn-service/proxy-ctrl/internal/consumer"
	"github.com/your-org/vpn-service/proxy-ctrl/internal/publisher"
	"github.com/your-org/vpn-service/proxy-ctrl/internal/service"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// Marzban client
	marzbanClient := marzban.NewClient(
		envOr("MARZBAN_BASE_URL", "http://localhost:8000"),
		envOr("MARZBAN_ADMIN_USER", "admin"),
		envOr("MARZBAN_ADMIN_PASSWORD", "marzban_dev_password"),
	)

	if err := marzbanClient.Authenticate(ctx); err != nil {
		log.Fatalf("marzban auth failed: %v", err)
	}
	log.Println("authenticated with Marzban")

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

	// Prefetch = 1 for fair dispatch
	if err := rabbitCh.Qos(1, 0, false); err != nil {
		log.Fatalf("set qos: %v", err)
	}

	// Dependencies
	marzbanAdapter := service.NewMarzbanAdapter(marzbanClient, envOr("XRAY_INBOUND_TAG", "VLESS_REALITY"), 0)
	// TODO: replace with Redis-based config repo
	repo := newInMemoryConfigRepo()
	pub := publisher.NewRabbitPublisher(rabbitCh)

	svc := service.NewProxyControlService(marzbanAdapter, repo, pub, 5, 3*time.Second)

	// Start consumer
	c := consumer.NewUserReadyConsumer(rabbitCh, svc)
	log.Println("Proxy Control Service starting...")

	if err := c.Start(ctx); err != nil && err != context.Canceled {
		log.Fatalf("consumer error: %v", err)
	}

	log.Println("Proxy Control Service stopped gracefully")
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Temporary in-memory repo for dev. Replace with Redis.
type inMemoryConfigRepo struct {
	configs map[string]*service.ProxyConfig
}

func newInMemoryConfigRepo() *inMemoryConfigRepo {
	return &inMemoryConfigRepo{configs: make(map[string]*service.ProxyConfig)}
}

func (r *inMemoryConfigRepo) Save(_ context.Context, config *service.ProxyConfig) error {
	r.configs[config.UserID] = config
	return nil
}

func (r *inMemoryConfigRepo) GetByUserID(_ context.Context, userID string) (*service.ProxyConfig, error) {
	config, ok := r.configs[userID]
	if !ok {
		return nil, nil
	}
	return config, nil
}

func (r *inMemoryConfigRepo) Delete(_ context.Context, userID string) error {
	delete(r.configs, userID)
	return nil
}
