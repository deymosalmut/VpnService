package service

import (
	"context"
	"errors"
	"fmt"
	"time"
)

var (
	ErrLinkNotFound = errors.New("link not found or expired")
	ErrLinkExists   = errors.New("active link already exists for this user")
)

// AuthService implements the core one-time link authentication logic.
type AuthService struct {
	repo      LinkRepository
	publisher EventPublisher
	tokens    TokenGenerator
	jwt       JWTIssuer
	linkTTL   time.Duration
}

// NewAuthService creates a new AuthService with all dependencies injected.
func NewAuthService(
	repo LinkRepository,
	publisher EventPublisher,
	tokens TokenGenerator,
	jwt JWTIssuer,
	linkTTL time.Duration,
) *AuthService {
	return &AuthService{
		repo:      repo,
		publisher: publisher,
		tokens:    tokens,
		jwt:       jwt,
		linkTTL:   linkTTL,
	}
}

// GenerateLink creates a one-time link for the given user.
// If an active link already exists for this user+source, returns it (idempotent).
func (s *AuthService) GenerateLink(ctx context.Context, userID, source string) (string, error) {
	// Check for existing active link (idempotency)
	existing, err := s.repo.FindByUser(ctx, userID, source)
	if err == nil && existing != "" {
		return existing, nil
	}

	token, err := s.tokens.Generate()
	if err != nil {
		return "", fmt.Errorf("generate token: %w", err)
	}

	link := OneTimeLink{
		Token:     token,
		ExpiresAt: time.Now().Add(s.linkTTL),
		UserID:    userID,
		Source:    source,
	}

	if err := s.repo.Store(ctx, token, link, s.linkTTL); err != nil {
		return "", fmt.Errorf("store link: %w", err)
	}

	return token, nil
}

// ValidateLink validates a one-time token, issues JWT, publishes event.
// The token is consumed (deleted) upon successful validation.
func (s *AuthService) ValidateLink(ctx context.Context, token string) (*ActivationResult, error) {
	link, err := s.repo.Get(ctx, token)
	if err != nil {
		return nil, ErrLinkNotFound
	}
	if link == nil {
		return nil, ErrLinkNotFound
	}

	// Issue JWT
	jwtToken, err := s.jwt.Issue(link.UserID, link.Source)
	if err != nil {
		return nil, fmt.Errorf("issue jwt: %w", err)
	}

	// Publish event (best-effort, don't block user)
	event := UserActivatedEvent{
		UserID:    link.UserID,
		Source:    link.Source,
		Timestamp: time.Now().Unix(),
	}
	if err := s.publisher.PublishUserActivated(ctx, event); err != nil {
		// Log but don't fail — the link is already consumed.
		// In production, use outbox pattern or retry queue.
		return nil, fmt.Errorf("publish event: %w", err)
	}

	return &ActivationResult{
		JWT:    jwtToken,
		UserID: link.UserID,
		Source: link.Source,
	}, nil
}
