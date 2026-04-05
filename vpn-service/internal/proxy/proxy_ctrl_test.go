package service_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/your-org/vpn-service/proxy-ctrl/internal/service"
)

// ============================================================
// Mocks
// ============================================================

type mockMarzban struct {
	users      map[string]*service.MarzbanUserResult
	createErr  error
	disableErr error
	deleteErr  error
	getErr     error
	callCount  int // tracks how many times CreateUser was called
}

func newMockMarzban() *mockMarzban {
	return &mockMarzban{
		users: make(map[string]*service.MarzbanUserResult),
	}
}

func (m *mockMarzban) Authenticate(_ context.Context) error { return nil }

func (m *mockMarzban) CreateUser(_ context.Context, userID string, plan string) (*service.MarzbanUserResult, error) {
	m.callCount++
	if m.createErr != nil {
		return nil, m.createErr
	}

	result := &service.MarzbanUserResult{
		Username:        "vpn_" + userID,
		SubscriptionURL: "https://marzban.example.com/sub/token123",
		Links:           []string{"vless://uuid@server:443?type=tcp&security=reality"},
		ExpiresAt:       time.Now().Add(30 * 24 * time.Hour),
	}
	m.users[userID] = result
	return result, nil
}

func (m *mockMarzban) DisableUser(_ context.Context, username string) error {
	if m.disableErr != nil {
		return m.disableErr
	}
	return nil
}

func (m *mockMarzban) DeleteUser(_ context.Context, username string) error {
	if m.deleteErr != nil {
		return m.deleteErr
	}
	return nil
}

func (m *mockMarzban) GetUser(_ context.Context, username string) (*service.MarzbanUserResult, error) {
	if m.getErr != nil {
		return nil, m.getErr
	}
	for _, u := range m.users {
		if u.Username == username {
			return u, nil
		}
	}
	return nil, errors.New("not found")
}

type mockConfigRepo struct {
	configs map[string]*service.ProxyConfig
	saveErr error
	getErr  error
	delErr  error
}

func newMockConfigRepo() *mockConfigRepo {
	return &mockConfigRepo{
		configs: make(map[string]*service.ProxyConfig),
	}
}

func (m *mockConfigRepo) Save(_ context.Context, config *service.ProxyConfig) error {
	if m.saveErr != nil {
		return m.saveErr
	}
	m.configs[config.UserID] = config
	return nil
}

func (m *mockConfigRepo) GetByUserID(_ context.Context, userID string) (*service.ProxyConfig, error) {
	if m.getErr != nil {
		return nil, m.getErr
	}
	config, ok := m.configs[userID]
	if !ok {
		return nil, errors.New("not found")
	}
	return config, nil
}

func (m *mockConfigRepo) Delete(_ context.Context, userID string) error {
	if m.delErr != nil {
		return m.delErr
	}
	delete(m.configs, userID)
	return nil
}

type mockPublisher struct {
	events     []service.ConfigReadyEvent
	publishErr error
}

func newMockPublisher() *mockPublisher {
	return &mockPublisher{}
}

func (m *mockPublisher) PublishConfigReady(_ context.Context, event service.ConfigReadyEvent) error {
	if m.publishErr != nil {
		return m.publishErr
	}
	m.events = append(m.events, event)
	return nil
}

// ============================================================
// Helper
// ============================================================

func setupService(mz *mockMarzban, repo *mockConfigRepo, pub *mockPublisher) *service.ProxyControlService {
	return service.NewProxyControlService(mz, repo, pub, 3, 10*time.Millisecond)
}

// ============================================================
// Test 1: ProvisionUser — happy path
// ============================================================

func TestProvisionUser_HappyPath(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	err := svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-001",
		Plan:   "30d",
	})

	require.NoError(t, err)

	// Config saved
	config, err := repo.GetByUserID(context.Background(), "user-001")
	require.NoError(t, err)
	assert.Equal(t, "vpn_user-001", config.MarzbanUsername)
	assert.Equal(t, "https://marzban.example.com/sub/token123", config.SubscriptionURL)
	assert.Len(t, config.Links, 1)

	// Event published
	require.Len(t, pub.events, 1)
	event := pub.events[0]
	assert.Equal(t, "user-001", event.UserID)
	assert.Equal(t, "vpn_user-001", event.MarzbanUsername)
	assert.Equal(t, "https://marzban.example.com/sub/token123", event.SubscriptionURL)
	assert.NotZero(t, event.Timestamp)
}

// ============================================================
// Test 2: ProvisionUser — idempotent (already provisioned)
// ============================================================

func TestProvisionUser_Idempotent(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	// Provision once
	err := svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-002",
		Plan:   "30d",
	})
	require.NoError(t, err)
	assert.Equal(t, 1, mz.callCount)

	// Provision again — should not call Marzban
	err = svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-002",
		Plan:   "30d",
	})
	require.NoError(t, err)
	assert.Equal(t, 1, mz.callCount, "Marzban should NOT be called again")

	// But event should be re-published (for Notification retry)
	assert.Len(t, pub.events, 2)
}

// ============================================================
// Test 3: ProvisionUser — retry on Marzban failure
// ============================================================

func TestProvisionUser_RetryOnFailure(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	// Fail first 2 attempts, succeed on 3rd
	callNum := 0
	mz.createErr = nil
	origCreate := mz.CreateUser
	_ = origCreate

	failCount := 2
	mzWrapper := &retryMockMarzban{
		inner:     mz,
		failCount: failCount,
	}

	svc := service.NewProxyControlService(mzWrapper, repo, pub, 3, 10*time.Millisecond)

	err := svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-retry",
		Plan:   "30d",
	})

	require.NoError(t, err)
	assert.Equal(t, 3, mzWrapper.callCount, "should have tried 3 times")
	assert.Len(t, pub.events, 1)
	_ = callNum
}

// retryMockMarzban fails the first N calls then delegates to inner.
type retryMockMarzban struct {
	inner     *mockMarzban
	failCount int
	callCount int
}

func (m *retryMockMarzban) Authenticate(ctx context.Context) error { return nil }
func (m *retryMockMarzban) DisableUser(ctx context.Context, username string) error {
	return m.inner.DisableUser(ctx, username)
}
func (m *retryMockMarzban) DeleteUser(ctx context.Context, username string) error {
	return m.inner.DeleteUser(ctx, username)
}
func (m *retryMockMarzban) GetUser(ctx context.Context, username string) (*service.MarzbanUserResult, error) {
	return m.inner.GetUser(ctx, username)
}
func (m *retryMockMarzban) CreateUser(ctx context.Context, userID string, plan string) (*service.MarzbanUserResult, error) {
	m.callCount++
	if m.callCount <= m.failCount {
		return nil, errors.New("marzban temporarily unavailable")
	}
	return m.inner.CreateUser(ctx, userID, plan)
}

// ============================================================
// Test 4: ProvisionUser — all retries exhausted
// ============================================================

func TestProvisionUser_AllRetriesExhausted(t *testing.T) {
	mz := newMockMarzban()
	mz.createErr = errors.New("marzban permanently down")
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	err := svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-fail",
		Plan:   "30d",
	})

	assert.Error(t, err)
	assert.ErrorIs(t, err, service.ErrProvisioningFailed)
	assert.Equal(t, 3, mz.callCount, "should have tried maxRetries times")

	// Nothing saved or published
	assert.Empty(t, repo.configs)
	assert.Empty(t, pub.events)
}

// ============================================================
// Test 5: DeprovisionUser — disables in Marzban, removes config
// ============================================================

func TestDeprovisionUser_HappyPath(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	// Provision first
	err := svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-deprov",
		Plan:   "30d",
	})
	require.NoError(t, err)
	assert.Len(t, repo.configs, 1)

	// Deprovision
	err = svc.DeprovisionUser(context.Background(), "user-deprov")
	require.NoError(t, err)

	// Config removed
	assert.Empty(t, repo.configs)
}

// ============================================================
// Test 6: DeprovisionUser — no config exists (no-op)
// ============================================================

func TestDeprovisionUser_NothingToDeprovision(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	err := svc.DeprovisionUser(context.Background(), "ghost-user")

	// Should not error — nothing to deprovision
	assert.NoError(t, err)
}

// ============================================================
// Test 7: GetConfig — returns stored config
// ============================================================

func TestGetConfig_ReturnsStored(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	_ = svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-get",
		Plan:   "90d",
	})

	config, err := svc.GetConfig(context.Background(), "user-get")
	require.NoError(t, err)
	assert.Equal(t, "user-get", config.UserID)
	assert.NotEmpty(t, config.SubscriptionURL)
	assert.NotEmpty(t, config.Links)
}

// ============================================================
// Test 8: RefreshConfig — updates from Marzban
// ============================================================

func TestRefreshConfig_UpdatesFromMarzban(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := setupService(mz, repo, pub)

	_ = svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-refresh",
		Plan:   "30d",
	})

	// Simulate Marzban updating the subscription URL (server rotation)
	mz.users["user-refresh"].SubscriptionURL = "https://new-server.example.com/sub/refreshed"

	config, err := svc.RefreshConfig(context.Background(), "user-refresh")
	require.NoError(t, err)
	assert.Equal(t, "https://new-server.example.com/sub/refreshed", config.SubscriptionURL)

	// Repo should have updated value
	stored := repo.configs["user-refresh"]
	assert.Equal(t, "https://new-server.example.com/sub/refreshed", stored.SubscriptionURL)
}

// ============================================================
// Test 9: Publish failure propagates
// ============================================================

func TestProvisionUser_PublishError_Propagates(t *testing.T) {
	mz := newMockMarzban()
	repo := newMockConfigRepo()
	pub := newMockPublisher()
	pub.publishErr = errors.New("rabbitmq connection lost")

	svc := setupService(mz, repo, pub)

	err := svc.ProvisionUser(context.Background(), service.UserReadyEvent{
		UserID: "user-puberr",
		Plan:   "30d",
	})

	assert.Error(t, err)
	assert.Contains(t, err.Error(), "publish config.ready")

	// Config WAS saved (Marzban user exists, we don't want to lose it)
	assert.Len(t, repo.configs, 1)
}

// ============================================================
// Test 10: Context cancellation stops retry loop
// ============================================================

func TestProvisionUser_ContextCancelled_StopsRetry(t *testing.T) {
	mz := newMockMarzban()
	mz.createErr = errors.New("marzban down")
	repo := newMockConfigRepo()
	pub := newMockPublisher()

	svc := service.NewProxyControlService(mz, repo, pub, 10, 50*time.Millisecond)

	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()

	err := svc.ProvisionUser(ctx, service.UserReadyEvent{
		UserID: "user-cancel",
		Plan:   "30d",
	})

	assert.Error(t, err)
	// Should have been cancelled before all 10 retries
	assert.Less(t, mz.callCount, 10, "should not exhaust all retries")
}
