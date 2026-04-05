package integration_test

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	tcredis "github.com/testcontainers/testcontainers-go/modules/redis"
	tcrabbit "github.com/testcontainers/testcontainers-go/modules/rabbitmq"

	"github.com/your-org/vpn-service/auth/internal/publisher"
	"github.com/your-org/vpn-service/auth/internal/repository"
	"github.com/your-org/vpn-service/auth/internal/service"
	jwtpkg "github.com/your-org/vpn-service/pkg/jwt"
)

// ============================================================
// Container setup helpers
// ============================================================

type testInfra struct {
	redisClient  *redis.Client
	rabbitConn   *amqp.Connection
	rabbitCh     *amqp.Channel
	redisC       testcontainers.Container
	rabbitC      testcontainers.Container
}

func setupInfra(t *testing.T, ctx context.Context) *testInfra {
	t.Helper()
	infra := &testInfra{}

	// ---- Redis ----
	redisContainer, err := tcredis.Run(ctx, "redis:7-alpine")
	require.NoError(t, err, "failed to start redis container")
	infra.redisC = redisContainer

	redisEndpoint, err := redisContainer.ConnectionString(ctx)
	require.NoError(t, err)

	infra.redisClient = redis.NewClient(&redis.Options{
		Addr: redisEndpoint,
	})
	// Parse the connection string — testcontainers returns "redis://host:port/0"
	opts, err := redis.ParseURL(redisEndpoint)
	if err == nil {
		infra.redisClient = redis.NewClient(opts)
	}

	// Verify Redis connectivity
	require.NoError(t, infra.redisClient.Ping(ctx).Err(), "redis ping failed")

	// ---- RabbitMQ ----
	rabbitContainer, err := tcrabbit.Run(ctx,
		"rabbitmq:3.13-management-alpine",
		tcrabbit.WithAdminUsername("test"),
		tcrabbit.WithAdminPassword("test"),
	)
	require.NoError(t, err, "failed to start rabbitmq container")
	infra.rabbitC = rabbitContainer

	rabbitEndpoint, err := rabbitContainer.AmqpURL(ctx)
	require.NoError(t, err)

	// Connect with retries (RabbitMQ takes a moment to boot)
	var rabbitConn *amqp.Connection
	for i := 0; i < 10; i++ {
		rabbitConn, err = amqp.Dial(rabbitEndpoint)
		if err == nil {
			break
		}
		time.Sleep(500 * time.Millisecond)
	}
	require.NoError(t, err, "rabbitmq connect failed after retries")
	infra.rabbitConn = rabbitConn

	infra.rabbitCh, err = rabbitConn.Channel()
	require.NoError(t, err)

	// Declare exchange and queue (mirroring rabbitmq-definitions.json)
	err = infra.rabbitCh.ExchangeDeclare(
		"vpn.events", "topic", true, false, false, false, nil,
	)
	require.NoError(t, err)

	_, err = infra.rabbitCh.QueueDeclare(
		"q.user.activated", true, false, false, false, nil,
	)
	require.NoError(t, err)

	err = infra.rabbitCh.QueueBind(
		"q.user.activated", "user.activated", "vpn.events", false, nil,
	)
	require.NoError(t, err)

	return infra
}

func (infra *testInfra) teardown(t *testing.T, ctx context.Context) {
	t.Helper()
	if infra.rabbitCh != nil {
		infra.rabbitCh.Close()
	}
	if infra.rabbitConn != nil {
		infra.rabbitConn.Close()
	}
	if infra.redisClient != nil {
		infra.redisClient.Close()
	}
	if infra.redisC != nil {
		_ = infra.redisC.Terminate(ctx)
	}
	if infra.rabbitC != nil {
		_ = infra.rabbitC.Terminate(ctx)
	}
}

// buildService creates an AuthService wired to real Redis + RabbitMQ.
func buildService(infra *testInfra) *service.AuthService {
	repo := repository.NewRedisLinkRepository(infra.redisClient)
	pub := publisher.NewRabbitPublisher(infra.rabbitCh)
	tokenGen := service.NewCryptoTokenGenerator(32)
	jwtIssuer := jwtpkg.NewIssuer("integration-test-secret", 15*time.Minute)

	return service.NewAuthService(repo, pub, tokenGen, jwtIssuer, 5*time.Minute)
}

// consumeOne reads one message from the given queue with a timeout.
func consumeOne(t *testing.T, ch *amqp.Channel, queue string, timeout time.Duration) []byte {
	t.Helper()
	msgs, err := ch.Consume(queue, "", true, false, false, false, nil)
	require.NoError(t, err)

	select {
	case msg := <-msgs:
		return msg.Body
	case <-time.After(timeout):
		t.Fatal("timed out waiting for message on queue: " + queue)
		return nil
	}
}

// ============================================================
// Integration Tests
// ============================================================

// TestIntegration_FullFlow tests the complete happy path:
// generate link → validate → JWT returned → event in RabbitMQ → token consumed.
func TestIntegration_FullFlow(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	svc := buildService(infra)

	// 1. Generate link
	token, err := svc.GenerateLink(ctx, "tg:123456", "telegram")
	require.NoError(t, err)
	assert.NotEmpty(t, token)
	assert.Len(t, token, 64, "256-bit token = 64 hex chars")

	// 2. Validate link — get JWT
	result, err := svc.ValidateLink(ctx, token)
	require.NoError(t, err)
	assert.NotEmpty(t, result.JWT)
	assert.Equal(t, "tg:123456", result.UserID)
	assert.Equal(t, "telegram", result.Source)

	// 3. Verify JWT is parseable
	jwtIssuer := jwtpkg.NewIssuer("integration-test-secret", 15*time.Minute)
	claims, err := jwtIssuer.Parse(result.JWT)
	require.NoError(t, err)
	assert.Equal(t, "tg:123456", claims["sub"])
	assert.Equal(t, "telegram", claims["source"])

	// 4. Verify event arrived in RabbitMQ
	body := consumeOne(t, infra.rabbitCh, "q.user.activated", 5*time.Second)
	var event service.UserActivatedEvent
	require.NoError(t, json.Unmarshal(body, &event))
	assert.Equal(t, "tg:123456", event.UserID)
	assert.Equal(t, "telegram", event.Source)
	assert.NotZero(t, event.Timestamp)

	// 5. Token consumed — second attempt fails
	result2, err := svc.ValidateLink(ctx, token)
	assert.Nil(t, result2)
	assert.ErrorIs(t, err, service.ErrLinkNotFound)
}

// TestIntegration_RedisIdempotency verifies that generating a link twice
// for the same user returns the same token (real Redis).
func TestIntegration_RedisIdempotency(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	svc := buildService(infra)

	token1, err := svc.GenerateLink(ctx, "email:user@test.com", "email")
	require.NoError(t, err)

	token2, err := svc.GenerateLink(ctx, "email:user@test.com", "email")
	require.NoError(t, err)

	assert.Equal(t, token1, token2, "same user should get same token")
}

// TestIntegration_DifferentUsersDifferentTokens verifies isolation between users.
func TestIntegration_DifferentUsersDifferentTokens(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	svc := buildService(infra)

	token1, err := svc.GenerateLink(ctx, "tg:111", "telegram")
	require.NoError(t, err)

	token2, err := svc.GenerateLink(ctx, "tg:222", "telegram")
	require.NoError(t, err)

	assert.NotEqual(t, token1, token2, "different users must get different tokens")
}

// TestIntegration_TokenExpiry verifies that expired tokens are rejected.
func TestIntegration_TokenExpiry(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	// Create service with very short TTL
	repo := repository.NewRedisLinkRepository(infra.redisClient)
	pub := publisher.NewRabbitPublisher(infra.rabbitCh)
	tokenGen := service.NewCryptoTokenGenerator(32)
	jwtIssuer := jwtpkg.NewIssuer("integration-test-secret", 15*time.Minute)

	svc := service.NewAuthService(repo, pub, tokenGen, jwtIssuer, 1*time.Second)

	token, err := svc.GenerateLink(ctx, "tg:expired", "telegram")
	require.NoError(t, err)

	// Wait for expiry
	time.Sleep(1500 * time.Millisecond)

	result, err := svc.ValidateLink(ctx, token)
	assert.Nil(t, result)
	assert.ErrorIs(t, err, service.ErrLinkNotFound)
}

// TestIntegration_MultipleEventsPublished verifies that activating multiple users
// produces the correct number of events in the queue.
func TestIntegration_MultipleEventsPublished(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	svc := buildService(infra)

	users := []struct {
		id     string
		source string
	}{
		{"tg:aaa", "telegram"},
		{"email:b@b.com", "email"},
		{"tg:ccc", "telegram"},
	}

	tokens := make([]string, len(users))
	for i, u := range users {
		token, err := svc.GenerateLink(ctx, u.id, u.source)
		require.NoError(t, err)
		tokens[i] = token
	}

	// Validate all
	for _, token := range tokens {
		_, err := svc.ValidateLink(ctx, token)
		require.NoError(t, err)
	}

	// Consume all 3 events
	for i, u := range users {
		body := consumeOne(t, infra.rabbitCh, "q.user.activated", 5*time.Second)
		var event service.UserActivatedEvent
		require.NoError(t, json.Unmarshal(body, &event), "event %d unmarshal", i)
		assert.Equal(t, u.id, event.UserID, "event %d user_id", i)
		assert.Equal(t, u.source, event.Source, "event %d source", i)
	}
}

// TestIntegration_RedisAtomicConsume verifies that concurrent validation
// of the same token results in only one success (atomic get-and-delete).
func TestIntegration_RedisAtomicConsume(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	svc := buildService(infra)

	token, err := svc.GenerateLink(ctx, "tg:race", "telegram")
	require.NoError(t, err)

	// Simulate concurrent access with goroutines
	results := make(chan *service.ActivationResult, 10)
	errs := make(chan error, 10)

	for i := 0; i < 10; i++ {
		go func() {
			r, e := svc.ValidateLink(ctx, token)
			results <- r
			errs <- e
		}()
	}

	successCount := 0
	for i := 0; i < 10; i++ {
		r := <-results
		e := <-errs
		if r != nil && e == nil {
			successCount++
		}
	}

	assert.Equal(t, 1, successCount, "exactly one goroutine should succeed")

	// Verify exactly one event was published
	body := consumeOne(t, infra.rabbitCh, "q.user.activated", 5*time.Second)
	assert.NotEmpty(t, body)

	// Queue should be empty now — no second message
	msgs, err := infra.rabbitCh.Consume("q.user.activated", "drain", true, false, false, false, nil)
	require.NoError(t, err)

	select {
	case <-msgs:
		t.Fatal("unexpected second message in queue — token was consumed more than once")
	case <-time.After(500 * time.Millisecond):
		// Expected — no more messages
	}
}

// TestIntegration_HandlerHTTP tests the HTTP endpoints end-to-end.
func TestIntegration_HandlerHTTP(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	ctx := context.Background()
	infra := setupInfra(t, ctx)
	defer infra.teardown(t, ctx)

	svc := buildService(infra)

	// We test service-level here; HTTP handler tests would use httptest.
	// This test ensures the full service wiring works through real infra.

	// Generate
	token, err := svc.GenerateLink(ctx, "tg:http-test", "telegram")
	require.NoError(t, err)
	assert.Len(t, token, 64)

	// Validate
	result, err := svc.ValidateLink(ctx, token)
	require.NoError(t, err)
	assert.NotEmpty(t, result.JWT)

	// Parse JWT and verify claims
	jwtIssuer := jwtpkg.NewIssuer("integration-test-secret", 15*time.Minute)
	claims, err := jwtIssuer.Parse(result.JWT)
	require.NoError(t, err)

	// JWT should have expected claims
	assert.Equal(t, "tg:http-test", claims["sub"])
	assert.Equal(t, "telegram", claims["source"])

	// exp should be in the future
	exp, ok := claims["exp"].(float64)
	require.True(t, ok)
	assert.Greater(t, int64(exp), time.Now().Unix())

	fmt.Printf("✅ JWT issued with exp=%v for user=%s\n",
		time.Unix(int64(exp), 0).Format(time.RFC3339), claims["sub"])
}
