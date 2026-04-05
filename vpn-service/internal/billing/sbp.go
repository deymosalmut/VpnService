package provider

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/your-org/vpn-service/billing/internal/service"
)

// SBPWebhookBody is the expected payload from the SBP gateway.
type SBPWebhookBody struct {
	OrderID string `json:"order_id"`
	Status  string `json:"status"` // "SUCCESS" | "FAIL"
	Amount  int64  `json:"amount"`
}

// SBPProvider implements service.PaymentProvider for SBP (Система быстрых платежей).
type SBPProvider struct {
	webhookSecret string
	baseURL       string // SBP gateway API URL
	merchantID    string
}

func NewSBPProvider(webhookSecret, baseURL, merchantID string) *SBPProvider {
	return &SBPProvider{
		webhookSecret: webhookSecret,
		baseURL:       baseURL,
		merchantID:    merchantID,
	}
}

func (p *SBPProvider) Name() string {
	return "sbp"
}

// CreateInvoice creates a payment order at the SBP gateway.
// In dev mode, returns a mock URL. In production, calls the actual SBP API.
func (p *SBPProvider) CreateInvoice(ctx context.Context, payment *service.Payment, plan *service.Plan) (string, string, error) {
	// TODO: implement actual SBP API call
	// For dev, return a mock payment URL
	providerTxID := "sbp_" + payment.ID
	paymentURL := fmt.Sprintf("%s/pay?order=%s&amount=%d&merchant=%s",
		p.baseURL, providerTxID, plan.Price, p.merchantID)
	return paymentURL, providerTxID, nil
}

// VerifyWebhook validates HMAC-SHA256 signature and parses the SBP callback.
func (p *SBPProvider) VerifyWebhook(rawBody []byte, signature string) (*service.WebhookPayload, error) {
	// Verify HMAC
	mac := hmac.New(sha256.New, []byte(p.webhookSecret))
	mac.Write(rawBody)
	expectedSig := hex.EncodeToString(mac.Sum(nil))

	if !hmac.Equal([]byte(signature), []byte(expectedSig)) {
		return nil, service.ErrInvalidSignature
	}

	var body SBPWebhookBody
	if err := json.Unmarshal(rawBody, &body); err != nil {
		return nil, fmt.Errorf("parse sbp webhook: %w", err)
	}

	status := "fail"
	if body.Status == "SUCCESS" {
		status = "success"
	}

	return &service.WebhookPayload{
		Provider:     "sbp",
		ProviderTxID: body.OrderID,
		Amount:       body.Amount,
		Currency:     "RUB",
		Status:       status,
		RawBody:      rawBody,
		Signature:    signature,
	}, nil
}
