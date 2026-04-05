package marzban

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sync"
	"time"
)

// Client is a Go client for the Marzban REST API.
type Client struct {
	baseURL    string
	username   string
	password   string
	httpClient *http.Client

	mu    sync.RWMutex
	token string
}

// NewClient creates a new Marzban API client.
func NewClient(baseURL, username, password string) *Client {
	return &Client{
		baseURL:  baseURL,
		username: username,
		password: password,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// ---- Auth ----

// TokenResponse is returned by POST /api/admin/token.
type TokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
}

// Authenticate obtains an admin JWT token.
func (c *Client) Authenticate(ctx context.Context) error {
	data := url.Values{}
	data.Set("username", c.username)
	data.Set("password", c.password)
	data.Set("grant_type", "password")

	req, err := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/api/admin/token", bytes.NewBufferString(data.Encode()))
	if err != nil {
		return fmt.Errorf("build auth request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("auth request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("auth failed (status %d): %s", resp.StatusCode, string(body))
	}

	var token TokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
		return fmt.Errorf("decode token: %w", err)
	}

	c.mu.Lock()
	c.token = token.AccessToken
	c.mu.Unlock()

	return nil
}

// doRequest performs an authenticated API request with auto-retry on 401.
func (c *Client) doRequest(ctx context.Context, method, path string, body interface{}) (*http.Response, error) {
	var bodyReader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("marshal body: %w", err)
		}
		bodyReader = bytes.NewReader(data)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}

	c.mu.RLock()
	token := c.token
	c.mu.RUnlock()

	req.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}

	// Auto-refresh token on 401
	if resp.StatusCode == http.StatusUnauthorized {
		resp.Body.Close()
		if err := c.Authenticate(ctx); err != nil {
			return nil, fmt.Errorf("re-authenticate: %w", err)
		}

		// Rebuild request
		if body != nil {
			data, _ := json.Marshal(body)
			bodyReader = bytes.NewReader(data)
		}
		req, _ = http.NewRequestWithContext(ctx, method, c.baseURL+path, bodyReader)
		c.mu.RLock()
		req.Header.Set("Authorization", "Bearer "+c.token)
		c.mu.RUnlock()
		if body != nil {
			req.Header.Set("Content-Type", "application/json")
		}
		resp, err = c.httpClient.Do(req)
		if err != nil {
			return nil, err
		}
	}

	return resp, nil
}

// ---- User CRUD ----

// UserCreate is the request body for creating a Marzban user.
type UserCreate struct {
	Username              string                       `json:"username"`
	Proxies               map[string]ProxySettings     `json:"proxies"`
	Inbounds              map[string][]string          `json:"inbounds"`
	Expire                *int64                       `json:"expire,omitempty"`   // Unix timestamp
	DataLimit             *int64                       `json:"data_limit,omitempty"` // bytes
	DataLimitResetStrategy string                      `json:"data_limit_reset_strategy,omitempty"`
	Status                string                       `json:"status"`
	Note                  string                       `json:"note,omitempty"`
}

// ProxySettings holds protocol-specific settings.
type ProxySettings struct {
	ID   string `json:"id,omitempty"`   // UUID for vmess/vless
	Flow string `json:"flow,omitempty"` // e.g. "xtls-rprx-vision" for VLESS Reality
}

// UserResponse is the full user object returned by Marzban API.
type UserResponse struct {
	Username              string                       `json:"username"`
	Proxies               map[string]ProxySettings     `json:"proxies"`
	Inbounds              map[string][]string          `json:"inbounds"`
	Expire                *int64                       `json:"expire"`
	DataLimit             *int64                       `json:"data_limit"`
	DataLimitResetStrategy string                      `json:"data_limit_reset_strategy"`
	Status                string                       `json:"status"`
	UsedTraffic           int64                        `json:"used_traffic"`
	LifetimeUsedTraffic   int64                        `json:"lifetime_used_traffic"`
	CreatedAt             string                       `json:"created_at"`
	Links                 []string                     `json:"links"`
	SubscriptionURL       string                       `json:"subscription_url"`
	Note                  string                       `json:"note"`
}

// CreateUser creates a new user in Marzban.
func (c *Client) CreateUser(ctx context.Context, user UserCreate) (*UserResponse, error) {
	resp, err := c.doRequest(ctx, "POST", "/api/user", user)
	if err != nil {
		return nil, fmt.Errorf("create user: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("create user failed (status %d): %s", resp.StatusCode, string(body))
	}

	var result UserResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode user: %w", err)
	}
	return &result, nil
}

// GetUser retrieves a user by username.
func (c *Client) GetUser(ctx context.Context, username string) (*UserResponse, error) {
	resp, err := c.doRequest(ctx, "GET", "/api/user/"+url.PathEscape(username), nil)
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("get user failed (status %d): %s", resp.StatusCode, string(body))
	}

	var result UserResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode user: %w", err)
	}
	return &result, nil
}

// UserModify is the request body for modifying a user.
type UserModify struct {
	Proxies               map[string]ProxySettings     `json:"proxies,omitempty"`
	Inbounds              map[string][]string          `json:"inbounds,omitempty"`
	Expire                *int64                       `json:"expire,omitempty"`
	DataLimit             *int64                       `json:"data_limit,omitempty"`
	DataLimitResetStrategy string                      `json:"data_limit_reset_strategy,omitempty"`
	Status                string                       `json:"status,omitempty"`
	Note                  string                       `json:"note,omitempty"`
}

// ModifyUser updates an existing user.
func (c *Client) ModifyUser(ctx context.Context, username string, mod UserModify) (*UserResponse, error) {
	resp, err := c.doRequest(ctx, "PUT", "/api/user/"+url.PathEscape(username), mod)
	if err != nil {
		return nil, fmt.Errorf("modify user: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("modify user failed (status %d): %s", resp.StatusCode, string(body))
	}

	var result UserResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode user: %w", err)
	}
	return &result, nil
}

// DeleteUser removes a user from Marzban.
func (c *Client) DeleteUser(ctx context.Context, username string) error {
	resp, err := c.doRequest(ctx, "DELETE", "/api/user/"+url.PathEscape(username), nil)
	if err != nil {
		return fmt.Errorf("delete user: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("delete user failed (status %d): %s", resp.StatusCode, string(body))
	}
	return nil
}

// DisableUser sets user status to "disabled".
func (c *Client) DisableUser(ctx context.Context, username string) (*UserResponse, error) {
	return c.ModifyUser(ctx, username, UserModify{Status: "disabled"})
}

// EnableUser sets user status to "active".
func (c *Client) EnableUser(ctx context.Context, username string) (*UserResponse, error) {
	return c.ModifyUser(ctx, username, UserModify{Status: "active"})
}

// ResetUserTraffic resets traffic counters for a user.
func (c *Client) ResetUserTraffic(ctx context.Context, username string) error {
	resp, err := c.doRequest(ctx, "POST", "/api/user/"+url.PathEscape(username)+"/reset", nil)
	if err != nil {
		return fmt.Errorf("reset traffic: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("reset traffic failed (status %d): %s", resp.StatusCode, string(body))
	}
	return nil
}

// ---- System ----

// SystemStats is returned by GET /api/system.
type SystemStats struct {
	Version       string `json:"version"`
	MemTotal      int64  `json:"mem_total"`
	MemUsed       int64  `json:"mem_used"`
	CPUUsage      float64 `json:"cpu_usage"`
	TotalUser     int    `json:"total_user"`
	UsersActive   int    `json:"users_active"`
	IncomingBW    int64  `json:"incoming_bandwidth"`
	OutgoingBW    int64  `json:"outgoing_bandwidth"`
}

// GetSystemStats returns Marzban system info.
func (c *Client) GetSystemStats(ctx context.Context) (*SystemStats, error) {
	resp, err := c.doRequest(ctx, "GET", "/api/system", nil)
	if err != nil {
		return nil, fmt.Errorf("get system stats: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("system stats failed (status %d): %s", resp.StatusCode, string(body))
	}

	var stats SystemStats
	if err := json.NewDecoder(resp.Body).Decode(&stats); err != nil {
		return nil, fmt.Errorf("decode stats: %w", err)
	}
	return &stats, nil
}

// ---- Inbounds ----

// GetInbounds returns available inbound configurations.
func (c *Client) GetInbounds(ctx context.Context) (map[string][]interface{}, error) {
	resp, err := c.doRequest(ctx, "GET", "/api/inbounds", nil)
	if err != nil {
		return nil, fmt.Errorf("get inbounds: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("get inbounds failed (status %d): %s", resp.StatusCode, string(body))
	}

	var result map[string][]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode inbounds: %w", err)
	}
	return result, nil
}
