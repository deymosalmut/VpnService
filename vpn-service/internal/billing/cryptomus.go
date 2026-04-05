package provider

import (
	"context"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/your-org/vpn-service/billing/internal/service"
)

// CryptomusWebhookBody is the callback payload from Cryptomus.
type CryptomusWebhookBody struct {
	OrderID string `json:"order_id"`
	Status  string `json:"status"` // "paid" | "paid_over" | "wrong_amount" | "cancel" | "fail"
	Amount  string `json:"amount"`
	Currency string `json:"currency"`
}

// CryptomusProvider implements service.PaymentProvider for Cryptomus.
type CryptomusProvider struct {
	apiKey     string
	merchantID string
	baseURL    string
}

func NewCryptomusProvider(apiKey, merchantID, baseURL string) *CryptomusProvider {
	return &CryptomusProvider{
		apiKey:     apiKey,
		merchantID: merchantID,
		baseURL:    baseURL,
	}
}

func (p *CryptomusProvider) Name() string {
	return "cryptomus"
}

// CreateInvoice creates a payment at Cryptomus.
// In dev mode, returns a mock URL. Production would POST to Cryptomus API.
func (p *CryptomusProvider) CreateInvoice(ctx context.Context, payment *service.Payment, plan *service.Plan) (string, string, error) {
	// TODO: implement actual Cryptomus API call
	// POST https://api.cryptomus.com/v1/payment
	providerTxID := "cm_" + payment.ID
	paymentURL := fmt.Sprintf("https://pay.cryptomus.com/pay/%s", providerTxID)
	return paymentURL, providerTxID, nil
}

// VerifyWebhook validates the Cryptomus webhook signature.
// Cryptomus signs webhooks with: md5(base64(json_body) + api_key)
func (p *CryptomusProvider) VerifyWebhook(rawBody []byte, signature string) (*service.WebhookPayload, error) {
	// Cryptomus signature: md5(base64(sorted_json_body) + api_key)
	var bodyMap map[string]interface{}
	if err := json.Unmarshal(rawBody, &bodyMap); err != nil {
		return nil, fmt.Errorf("parse cryptomus webhook: %w", err)
	}

	// Remove "sign" field from body before verification
	delete(bodyMap, "sign")

	// Sort keys and re-encode
	sortedBody, err := jsonMarshalSorted(bodyMap)
	if err != nil {
		return nil, fmt.Errorf("sort json: %w", err)
	}

	encoded := base64.StdEncoding.EncodeToString(sortedBody)
	hash := md5.Sum([]byte(encoded + p.apiKey))
	expectedSig := hex.EncodeToString(hash[:])

	if !strings.EqualFold(signature, expectedSig) {
		return nil, service.ErrInvalidSignature
	}

	var body CryptomusWebhookBody
	if err := json.Unmarshal(rawBody, &body); err != nil {
		return nil, fmt.Errorf("parse cryptomus body: %w", err)
	}

	status := "fail"
	if body.Status == "paid" || body.Status == "paid_over" {
		status = "success"
	}

	return &service.WebhookPayload{
		Provider:     "cryptomus",
		ProviderTxID: body.OrderID,
		Currency:     body.Currency,
		Status:       status,
		RawBody:      rawBody,
		Signature:    signature,
	}, nil
}

// jsonMarshalSorted produces JSON with sorted keys (required by Cryptomus signature).
func jsonMarshalSorted(m map[string]interface{}) ([]byte, error) {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	sorted := make(map[string]interface{}, len(m))
	for _, k := range keys {
		sorted[k] = m[k]
	}
	return json.Marshal(sorted)
}
