package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/your-org/vpn-service/proxy-ctrl/internal/service"
)

const prefix = "proxy:config:"

// RedisConfigRepository implements service.ConfigRepository using Redis.
type RedisConfigRepository struct {
	client *redis.Client
	ttl    time.Duration
}

func NewRedisConfigRepository(client *redis.Client, ttl time.Duration) *RedisConfigRepository {
	return &RedisConfigRepository{client: client, ttl: ttl}
}

func (r *RedisConfigRepository) Save(ctx context.Context, config *service.ProxyConfig) error {
	data, err := json.Marshal(config)
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}
	return r.client.Set(ctx, prefix+config.UserID, data, r.ttl).Err()
}

func (r *RedisConfigRepository) GetByUserID(ctx context.Context, userID string) (*service.ProxyConfig, error) {
	data, err := r.client.Get(ctx, prefix+userID).Bytes()
	if err == redis.Nil {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("redis get: %w", err)
	}

	var config service.ProxyConfig
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, fmt.Errorf("unmarshal config: %w", err)
	}
	return &config, nil
}

func (r *RedisConfigRepository) Delete(ctx context.Context, userID string) error {
	return r.client.Del(ctx, prefix+userID).Err()
}
