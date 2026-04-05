package service

import (
	"context"
	"fmt"
	"time"

	"github.com/your-org/vpn-service/pkg/marzban"
)

// planDurations maps plan IDs to their duration.
var planDurations = map[string]time.Duration{
	"30d":  30 * 24 * time.Hour,
	"90d":  90 * 24 * time.Hour,
	"365d": 365 * 24 * time.Hour,
}

// MarzbanAdapter wraps the shared marzban.Client to implement MarzbanClient.
type MarzbanAdapter struct {
	client       *marzban.Client
	inboundTag   string // e.g. "VLESS_REALITY"
	dataLimitGB  int64  // per-user data limit, 0 = unlimited
}

// NewMarzbanAdapter creates an adapter around the real Marzban client.
func NewMarzbanAdapter(client *marzban.Client, inboundTag string, dataLimitGB int64) *MarzbanAdapter {
	return &MarzbanAdapter{
		client:      client,
		inboundTag:  inboundTag,
		dataLimitGB: dataLimitGB,
	}
}

func (a *MarzbanAdapter) Authenticate(ctx context.Context) error {
	return a.client.Authenticate(ctx)
}

func (a *MarzbanAdapter) CreateUser(ctx context.Context, userID string, plan string) (*MarzbanUserResult, error) {
	duration, ok := planDurations[plan]
	if !ok {
		return nil, fmt.Errorf("unknown plan: %s", plan)
	}

	expireAt := time.Now().Add(duration)
	username := marzban.UsernameFromUserID(userID)

	userCreate := marzban.NewVLESSRealityUser(username, expireAt, a.dataLimitGB, a.inboundTag)

	resp, err := a.client.CreateUser(ctx, userCreate)
	if err != nil {
		return nil, fmt.Errorf("marzban create user: %w", err)
	}

	return &MarzbanUserResult{
		Username:        resp.Username,
		SubscriptionURL: resp.SubscriptionURL,
		Links:           resp.Links,
		ExpiresAt:       expireAt,
	}, nil
}

func (a *MarzbanAdapter) DisableUser(ctx context.Context, username string) error {
	_, err := a.client.DisableUser(ctx, username)
	return err
}

func (a *MarzbanAdapter) DeleteUser(ctx context.Context, username string) error {
	return a.client.DeleteUser(ctx, username)
}

func (a *MarzbanAdapter) GetUser(ctx context.Context, username string) (*MarzbanUserResult, error) {
	resp, err := a.client.GetUser(ctx, username)
	if err != nil {
		return nil, err
	}
	if resp == nil {
		return nil, fmt.Errorf("user not found: %s", username)
	}

	var expiresAt time.Time
	if resp.Expire != nil {
		expiresAt = time.Unix(*resp.Expire, 0)
	}

	return &MarzbanUserResult{
		Username:        resp.Username,
		SubscriptionURL: resp.SubscriptionURL,
		Links:           resp.Links,
		ExpiresAt:       expiresAt,
	}, nil
}
