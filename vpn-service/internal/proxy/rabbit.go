package publisher

import (
	"context"
	"encoding/json"
	"fmt"

	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/your-org/vpn-service/proxy-ctrl/internal/service"
)

const (
	exchangeName = "vpn.events"
	routingKey   = "config.ready"
)

type RabbitPublisher struct {
	ch *amqp.Channel
}

func NewRabbitPublisher(ch *amqp.Channel) *RabbitPublisher {
	return &RabbitPublisher{ch: ch}
}

func (p *RabbitPublisher) PublishConfigReady(ctx context.Context, event service.ConfigReadyEvent) error {
	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}

	return p.ch.PublishWithContext(ctx,
		exchangeName,
		routingKey,
		false,
		false,
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent,
			Body:         body,
		},
	)
}
