package service

import (
	"context"
	"fmt"
	"time"
)

// ProxyControlService handles user provisioning in Marzban.
type ProxyControlService struct {
	marzban    MarzbanClient
	repo       ConfigRepository
	publisher  EventPublisher
	maxRetries int
	retryDelay time.Duration
}

// NewProxyControlService creates a ProxyControlService with all dependencies.
func NewProxyControlService(
	marzban MarzbanClient,
	repo ConfigRepository,
	publisher EventPublisher,
	maxRetries int,
	retryDelay time.Duration,
) *ProxyControlService {
	if maxRetries <= 0 {
		maxRetries = 3
	}
	if retryDelay <= 0 {
		retryDelay = 2 * time.Second
	}
	return &ProxyControlService{
		marzban:    marzban,
		repo:       repo,
		publisher:  publisher,
		maxRetries: maxRetries,
		retryDelay: retryDelay,
	}
}

// ProvisionUser creates a Marzban user, stores config, publishes event.
// This is called when a user.ready_for_proxy event is received.
func (s *ProxyControlService) ProvisionUser(ctx context.Context, event UserReadyEvent) error {
	// Idempotency: check if already provisioned
	existing, err := s.repo.GetByUserID(ctx, event.UserID)
	if err == nil && existing != nil {
		// Already provisioned — re-publish event (in case Notification missed it)
		return s.publishConfig(ctx, existing)
	}

	// Create user in Marzban with retry
	var result *MarzbanUserResult
	var lastErr error

	for attempt := 1; attempt <= s.maxRetries; attempt++ {
		result, lastErr = s.marzban.CreateUser(ctx, event.UserID, event.Plan)
		if lastErr == nil {
			break
		}

		if attempt < s.maxRetries {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(s.retryDelay * time.Duration(attempt)): // exponential backoff
			}
		}
	}

	if lastErr != nil {
		return fmt.Errorf("%w: %v (after %d retries)", ErrProvisioningFailed, lastErr, s.maxRetries)
	}

	// Store config
	config := &ProxyConfig{
		UserID:          event.UserID,
		MarzbanUsername: result.Username,
		SubscriptionURL: result.SubscriptionURL,
		Links:           result.Links,
		ExpiresAt:       result.ExpiresAt,
		CreatedAt:       time.Now(),
	}

	if err := s.repo.Save(ctx, config); err != nil {
		return fmt.Errorf("save config: %w", err)
	}

	// Publish config.ready
	return s.publishConfig(ctx, config)
}

// DeprovisionUser disables a user in Marzban and removes local config.
func (s *ProxyControlService) DeprovisionUser(ctx context.Context, userID string) error {
	config, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return fmt.Errorf("get config: %w", err)
	}
	if config == nil {
		return nil // nothing to deprovision
	}

	// Disable in Marzban (don't delete — keep for traffic logs)
	if err := s.marzban.DisableUser(ctx, config.MarzbanUsername); err != nil {
		return fmt.Errorf("disable marzban user: %w", err)
	}

	if err := s.repo.Delete(ctx, userID); err != nil {
		return fmt.Errorf("delete local config: %w", err)
	}

	return nil
}

// GetConfig returns the proxy config for a user.
func (s *ProxyControlService) GetConfig(ctx context.Context, userID string) (*ProxyConfig, error) {
	config, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, err
	}
	return config, nil
}

// RefreshConfig re-fetches config from Marzban (e.g. after server rotation).
func (s *ProxyControlService) RefreshConfig(ctx context.Context, userID string) (*ProxyConfig, error) {
	config, err := s.repo.GetByUserID(ctx, userID)
	if err != nil || config == nil {
		return nil, fmt.Errorf("user not provisioned")
	}

	result, err := s.marzban.GetUser(ctx, config.MarzbanUsername)
	if err != nil {
		return nil, fmt.Errorf("fetch from marzban: %w", err)
	}

	config.SubscriptionURL = result.SubscriptionURL
	config.Links = result.Links
	config.ExpiresAt = result.ExpiresAt

	if err := s.repo.Save(ctx, config); err != nil {
		return nil, fmt.Errorf("update config: %w", err)
	}

	return config, nil
}

func (s *ProxyControlService) publishConfig(ctx context.Context, config *ProxyConfig) error {
	event := ConfigReadyEvent{
		UserID:          config.UserID,
		MarzbanUsername: config.MarzbanUsername,
		SubscriptionURL: config.SubscriptionURL,
		Links:           config.Links,
		Timestamp:       time.Now().Unix(),
	}
	if err := s.publisher.PublishConfigReady(ctx, event); err != nil {
		return fmt.Errorf("publish config.ready: %w", err)
	}
	return nil
}
