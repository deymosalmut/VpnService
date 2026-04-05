package service

import (
	"context"
	"time"
)

// OneTimeLink represents a generated one-time authentication link.
type OneTimeLink struct {
	Token     string
	ExpiresAt time.Time
	UserID    string // external ID: telegram_id or email
	Source    string // "telegram" | "email"
}

// ActivationResult is returned after successful link validation.
type ActivationResult struct {
	JWT    string
	UserID string
	Source string
}

// UserActivatedEvent is published to RabbitMQ after successful validation.
type UserActivatedEvent struct {
	UserID    string `json:"user_id"`
	Source    string `json:"source"`
	Timestamp int64  `json:"timestamp"`
}

// LinkRepository abstracts one-time link storage (Redis).
type LinkRepository interface {
	// Store saves a token with TTL. Returns error if token already exists.
	Store(ctx context.Context, token string, link OneTimeLink, ttl time.Duration) error

	// Get retrieves and deletes the token atomically (consume-once).
	Get(ctx context.Context, token string) (*OneTimeLink, error)

	// Exists checks if a link already exists for the given user+source.
	FindByUser(ctx context.Context, userID, source string) (string, error)
}

// EventPublisher abstracts message publishing (RabbitMQ).
type EventPublisher interface {
	// PublishUserActivated sends the user.activated event.
	PublishUserActivated(ctx context.Context, event UserActivatedEvent) error
}

// TokenGenerator abstracts secure token generation.
type TokenGenerator interface {
	Generate() (string, error)
}

// JWTIssuer abstracts JWT creation.
type JWTIssuer interface {
	Issue(userID, source string) (string, error)
}
