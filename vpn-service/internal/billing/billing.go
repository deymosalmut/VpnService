package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// BillingService handles payment creation and webhook processing.
type BillingService struct {
	repo      PaymentRepository
	publisher EventPublisher
	plans     PlanRegistry
	providers map[string]PaymentProvider
}

// NewBillingService creates a new BillingService with all dependencies.
func NewBillingService(
	repo PaymentRepository,
	publisher EventPublisher,
	plans PlanRegistry,
	providers ...PaymentProvider,
) *BillingService {
	provMap := make(map[string]PaymentProvider, len(providers))
	for _, p := range providers {
		provMap[p.Name()] = p
	}
	return &BillingService{
		repo:      repo,
		publisher: publisher,
		plans:     plans,
		providers: provMap,
	}
}

// CreatePayment initiates a new payment: validates plan, calls provider, stores record.
func (s *BillingService) CreatePayment(ctx context.Context, req CreatePaymentRequest) (*CreatePaymentResult, error) {
	// Validate provider
	provider, ok := s.providers[req.Provider]
	if !ok {
		return nil, ErrInvalidProvider
	}

	// Validate plan
	plan, err := s.plans.Get(req.PlanID)
	if err != nil {
		return nil, ErrInvalidPlan
	}

	// Create payment record
	payment := &Payment{
		ID:        uuid.New().String(),
		UserID:    req.UserID,
		Provider:  req.Provider,
		Amount:    plan.Price,
		Currency:  plan.Currency,
		PlanID:    req.PlanID,
		Status:    "pending",
		CreatedAt: time.Now(),
	}

	// Call provider to create invoice
	paymentURL, providerTxID, err := provider.CreateInvoice(ctx, payment, plan)
	if err != nil {
		return nil, fmt.Errorf("create invoice: %w", err)
	}
	payment.ProviderTxID = providerTxID

	// Persist
	if err := s.repo.Create(ctx, payment); err != nil {
		return nil, fmt.Errorf("store payment: %w", err)
	}

	return &CreatePaymentResult{
		PaymentID:  payment.ID,
		PaymentURL: paymentURL,
		Provider:   req.Provider,
	}, nil
}

// HandleWebhook processes an incoming payment webhook from any provider.
func (s *BillingService) HandleWebhook(ctx context.Context, providerName string, rawBody []byte, signature string) error {
	// Find provider
	provider, ok := s.providers[providerName]
	if !ok {
		return ErrInvalidProvider
	}

	// Verify signature and parse
	payload, err := provider.VerifyWebhook(rawBody, signature)
	if err != nil {
		return ErrInvalidSignature
	}

	// Find existing payment
	payment, err := s.repo.GetByProviderTx(ctx, providerName, payload.ProviderTxID)
	if err != nil {
		return ErrPaymentNotFound
	}

	// Idempotency: skip if already confirmed
	if payment.Status == "confirmed" {
		return ErrPaymentAlreadyDone
	}

	// Update status based on provider response
	if payload.Status != "success" {
		now := time.Now()
		return s.repo.UpdateStatus(ctx, payment.ID, "failed", &now)
	}

	// Mark as confirmed
	now := time.Now()
	if err := s.repo.UpdateStatus(ctx, payment.ID, "confirmed", &now); err != nil {
		return fmt.Errorf("update payment status: %w", err)
	}

	// Publish event
	event := PaymentConfirmedEvent{
		UserID:    payment.UserID,
		PaymentID: payment.ID,
		Plan:      payment.PlanID,
		Amount:    payment.Amount,
		Currency:  payment.Currency,
		Provider:  providerName,
		Timestamp: now.Unix(),
	}
	if err := s.publisher.PublishPaymentConfirmed(ctx, event); err != nil {
		return fmt.Errorf("publish event: %w", err)
	}

	return nil
}

// GetPayment returns payment details by ID.
func (s *BillingService) GetPayment(ctx context.Context, paymentID string) (*Payment, error) {
	payment, err := s.repo.GetByID(ctx, paymentID)
	if err != nil {
		return nil, ErrPaymentNotFound
	}
	return payment, nil
}

// ListPlans returns all available subscription plans.
func (s *BillingService) ListPlans() []Plan {
	return s.plans.List()
}
