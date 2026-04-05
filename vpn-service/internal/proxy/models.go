package service

import (
	"context"
	"errors"
	"time"
)

var (
	ErrUserAlreadyProvisioned = errors.New("user already has proxy config")
	ErrProvisioningFailed     = errors.New("failed to provision proxy config")
	ErrMarzbanUnavailable     = errors.New("marzban API is unavailable")
)

// UserReadyEvent is consumed from RabbitMQ (published by User Management).
type UserReadyEvent struct {
	UserID string `json:"user_id"`
	Plan   string `json:"plan"`   // "30d" | "90d" | "365d"
}

// ConfigReadyEvent is published to RabbitMQ after provisioning.
type ConfigReadyEvent struct {
	UserID          string `json:"user_id"`
	MarzbanUsername string `json:"marzban_username"`
	SubscriptionURL string `json:"subscription_url"`
	Links           []string `json:"links"`
	Timestamp       int64  `json:"timestamp"`
}

// ProxyConfig represents a provisioned proxy configuration.
type ProxyConfig struct {
	UserID          string
	MarzbanUsername string
	SubscriptionURL string
	Links           []string
	ExpiresAt       time.Time
	CreatedAt       time.Time
}

// ConfigRepository stores provisioned proxy configs.
type ConfigRepository interface {
	Save(ctx context.Context, config *ProxyConfig) error
	GetByUserID(ctx context.Context, userID string) (*ProxyConfig, error)
	Delete(ctx context.Context, userID string) error
}

// MarzbanClient abstracts the Marzban API for testability.
type MarzbanClient interface {
	Authenticate(ctx context.Context) error
	CreateUser(ctx context.Context, username string, plan string) (*MarzbanUserResult, error)
	DisableUser(ctx context.Context, username string) error
	DeleteUser(ctx context.Context, username string) error
	GetUser(ctx context.Context, username string) (*MarzbanUserResult, error)
}

// MarzbanUserResult is the normalized result of creating/getting a Marzban user.
type MarzbanUserResult struct {
	Username        string
	SubscriptionURL string
	Links           []string
	ExpiresAt       time.Time
}

// EventPublisher publishes config.ready events.
type EventPublisher interface {
	PublishConfigReady(ctx context.Context, event ConfigReadyEvent) error
}
