package consumer

import (
	"context"
	"encoding/json"
	"log"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/your-org/vpn-service/proxy-ctrl/internal/service"
)

// UserReadyConsumer listens to the q.user.ready_for_proxy queue
// and calls ProxyControlService.ProvisionUser for each message.
type UserReadyConsumer struct {
	ch  *amqp.Channel
	svc *service.ProxyControlService
}

func NewUserReadyConsumer(ch *amqp.Channel, svc *service.ProxyControlService) *UserReadyConsumer {
	return &UserReadyConsumer{ch: ch, svc: svc}
}

// Start begins consuming messages. Blocks until ctx is cancelled.
func (c *UserReadyConsumer) Start(ctx context.Context) error {
	msgs, err := c.ch.Consume(
		"q.user.ready_for_proxy",
		"proxy-ctrl-consumer",
		false, // manual ack
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return err
	}

	log.Println("proxy-ctrl consumer started, waiting for user.ready_for_proxy events...")

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case msg, ok := <-msgs:
			if !ok {
				return nil // channel closed
			}
			c.handleMessage(ctx, msg)
		}
	}
}

func (c *UserReadyConsumer) handleMessage(ctx context.Context, msg amqp.Delivery) {
	var event service.UserReadyEvent
	if err := json.Unmarshal(msg.Body, &event); err != nil {
		log.Printf("ERROR: unmarshal user.ready event: %v (body: %s)", err, string(msg.Body))
		// Nack without requeue — bad message format won't fix itself
		_ = msg.Nack(false, false)
		return
	}

	log.Printf("provisioning user: %s (plan: %s)", event.UserID, event.Plan)

	if err := c.svc.ProvisionUser(ctx, event); err != nil {
		log.Printf("ERROR: provision user %s: %v", event.UserID, err)
		// Nack with requeue — transient errors (Marzban down) should be retried
		_ = msg.Nack(false, true)
		return
	}

	log.Printf("user %s provisioned successfully", event.UserID)
	_ = msg.Ack(false)
}
