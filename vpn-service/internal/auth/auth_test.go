package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/your-org/vpn-service/auth/internal/service"
)

// ============================================================
// Mocks
// ============================================================

// mockRepo is an in-memory LinkRepository for testing.
type mockRepo struct {
	links    map[string]service.OneTimeLink // token -> link
	userIdx  map[string]string             // "userID:source" -> token
	getErr   error                         // force error on Get
	storeErr error                         // force error on Store
}

func newMockRepo() *mockRepo {
	return &mockRepo{
		links:   make(map[string]service.OneTimeLink),
		userIdx: make(map[string]string),
	}
}

func (m *mockRepo) Store(_ context.Context, token string, link service.OneTimeLink, _ time.Duration) error {
	if m.storeErr != nil {
		return m.storeErr
	}
	m.links[token] = link
	m.userIdx[link.UserID+":"+link.Source] = token
	return nil
}

func (m *mockRepo) Get(_ context.Context, token string) (*service.OneTimeLink, error) {
	if m.getErr != nil {
		return nil, m.getErr
	}
	link, ok := m.links[token]
	if !ok {
		return nil, errors.New("not found")
	}
	// Simulate atomic get-and-delete
	delete(m.links, token)
	delete(m.userIdx, link.UserID+":"+link.Source)
	return &link, nil
}

func (m *mockRepo) FindByUser(_ context.Context, userID, source string) (string, error) {
	token, ok := m.userIdx[userID+":"+source]
	if !ok {
		return "", errors.New("not found")
	}
	return token, nil
}

// mockPublisher records published events for assertions.
type mockPublisher struct {
	events    []service.UserActivatedEvent
	publishErr error
}

func newMockPublisher() *mockPublisher {
	return &mockPublisher{}
}

func (m *mockPublisher) PublishUserActivated(_ context.Context, event service.UserActivatedEvent) error {
	if m.publishErr != nil {
		return m.publishErr
	}
	m.events = append(m.events, event)
	return nil
}

// mockTokenGen returns predictable tokens for testing.
type mockTokenGen struct {
	nextToken string
	err       error
}

func (m *mockTokenGen) Generate() (string, error) {
	if m.err != nil {
		return "", m.err
	}
	return m.nextToken, nil
}

// mockJWT returns predictable JWTs for testing.
type mockJWT struct {
	nextJWT string
	err     error
}

func (m *mockJWT) Issue(userID, source string) (string, error) {
	if m.err != nil {
		return "", m.err
	}
	return m.nextJWT, nil
}

// ============================================================
// Helper
// ============================================================

func setupService(repo *mockRepo, pub *mockPublisher, tokenGen *mockTokenGen, jwt *mockJWT) *service.AuthService {
	return service.NewAuthService(
		repo,
		pub,
		tokenGen,
		jwt,
		5*time.Minute,
	)
}

// ============================================================
// Test 1: GenerateLink creates a unique token and stores it
// ============================================================

func TestGenerateLink_CreatesUniqueToken(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{nextToken: "abc123-unique-token"}
	jwt := &mockJWT{}

	svc := setupService(repo, pub, tokenGen, jwt)

	token, err := svc.GenerateLink(context.Background(), "telegram:12345", "telegram")

	require.NoError(t, err)
	assert.Equal(t, "abc123-unique-token", token)

	// Verify it was stored in repo
	stored, ok := repo.links["abc123-unique-token"]
	assert.True(t, ok, "token should be stored in repository")
	assert.Equal(t, "telegram:12345", stored.UserID)
	assert.Equal(t, "telegram", stored.Source)
}

// ============================================================
// Test 2: GenerateLink is idempotent (returns existing token)
// ============================================================

func TestGenerateLink_Idempotent_ReturnExisting(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{nextToken: "first-token"}
	jwt := &mockJWT{}

	svc := setupService(repo, pub, tokenGen, jwt)

	// First call — creates
	token1, err := svc.GenerateLink(context.Background(), "user@example.com", "email")
	require.NoError(t, err)
	assert.Equal(t, "first-token", token1)

	// Change what token generator would return
	tokenGen.nextToken = "second-token"

	// Second call — should return existing, not create new
	token2, err := svc.GenerateLink(context.Background(), "user@example.com", "email")
	require.NoError(t, err)
	assert.Equal(t, "first-token", token2, "should return existing token, not generate new")

	// Only one token in repo
	assert.Len(t, repo.links, 1)
}

// ============================================================
// Test 3: ValidateLink returns JWT and deletes token
// ============================================================

func TestValidateLink_ReturnsJWT_DeletesToken(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{nextToken: "valid-token"}
	jwt := &mockJWT{nextJWT: "eyJhbGciOiJIUzI1NiJ9.test-jwt-token"}

	svc := setupService(repo, pub, tokenGen, jwt)

	// Generate a link first
	_, err := svc.GenerateLink(context.Background(), "telegram:99999", "telegram")
	require.NoError(t, err)

	// Validate it
	result, err := svc.ValidateLink(context.Background(), "valid-token")

	require.NoError(t, err)
	assert.Equal(t, "eyJhbGciOiJIUzI1NiJ9.test-jwt-token", result.JWT)
	assert.Equal(t, "telegram:99999", result.UserID)
	assert.Equal(t, "telegram", result.Source)

	// Token should be consumed (deleted from repo)
	_, ok := repo.links["valid-token"]
	assert.False(t, ok, "token should be deleted after validation")
}

// ============================================================
// Test 4: ValidateLink publishes user.activated event
// ============================================================

func TestValidateLink_PublishesUserActivatedEvent(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{nextToken: "event-token"}
	jwt := &mockJWT{nextJWT: "some-jwt"}

	svc := setupService(repo, pub, tokenGen, jwt)

	_, err := svc.GenerateLink(context.Background(), "telegram:77777", "telegram")
	require.NoError(t, err)

	_, err = svc.ValidateLink(context.Background(), "event-token")
	require.NoError(t, err)

	// Check that event was published
	require.Len(t, pub.events, 1, "exactly one event should be published")

	event := pub.events[0]
	assert.Equal(t, "telegram:77777", event.UserID)
	assert.Equal(t, "telegram", event.Source)
	assert.NotZero(t, event.Timestamp, "timestamp should be set")
}

// ============================================================
// Test 5: ValidateLink with invalid/expired token returns error
// ============================================================

func TestValidateLink_InvalidToken_ReturnsError(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{}
	jwt := &mockJWT{}

	svc := setupService(repo, pub, tokenGen, jwt)

	result, err := svc.ValidateLink(context.Background(), "nonexistent-token")

	assert.Nil(t, result)
	assert.ErrorIs(t, err, service.ErrLinkNotFound)

	// No events should be published
	assert.Empty(t, pub.events, "no events should be published for invalid tokens")
}

// ============================================================
// Test 6: ValidateLink — same token cannot be used twice
// ============================================================

func TestValidateLink_TokenConsumedOnce(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{nextToken: "once-token"}
	jwt := &mockJWT{nextJWT: "jwt-once"}

	svc := setupService(repo, pub, tokenGen, jwt)

	_, err := svc.GenerateLink(context.Background(), "telegram:11111", "telegram")
	require.NoError(t, err)

	// First validation — OK
	result, err := svc.ValidateLink(context.Background(), "once-token")
	require.NoError(t, err)
	assert.NotNil(t, result)

	// Second validation — should fail
	result2, err := svc.ValidateLink(context.Background(), "once-token")
	assert.Nil(t, result2)
	assert.ErrorIs(t, err, service.ErrLinkNotFound)

	// Only one event published (from the first validation)
	assert.Len(t, pub.events, 1)
}

// ============================================================
// Test 7: GenerateLink fails if token generation fails
// ============================================================

func TestGenerateLink_TokenGenError_ReturnsError(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	tokenGen := &mockTokenGen{err: errors.New("entropy source unavailable")}
	jwt := &mockJWT{}

	svc := setupService(repo, pub, tokenGen, jwt)

	token, err := svc.GenerateLink(context.Background(), "telegram:55555", "telegram")

	assert.Empty(t, token)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "generate token")
}

// ============================================================
// Test 8: ValidateLink — event publish failure propagates error
// ============================================================

func TestValidateLink_PublishError_ReturnsError(t *testing.T) {
	repo := newMockRepo()
	pub := newMockPublisher()
	pub.publishErr = errors.New("rabbitmq connection lost")
	tokenGen := &mockTokenGen{nextToken: "pub-fail-token"}
	jwt := &mockJWT{nextJWT: "jwt-ok"}

	svc := setupService(repo, pub, tokenGen, jwt)

	_, err := svc.GenerateLink(context.Background(), "telegram:44444", "telegram")
	require.NoError(t, err)

	result, err := svc.ValidateLink(context.Background(), "pub-fail-token")

	assert.Nil(t, result)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "publish event")
}
