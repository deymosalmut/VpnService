package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/lib/pq"

	"github.com/your-org/vpn-service/billing/internal/service"
)

// PostgresPaymentRepository implements service.PaymentRepository.
type PostgresPaymentRepository struct {
	db *sql.DB
}

func NewPostgresPaymentRepository(db *sql.DB) *PostgresPaymentRepository {
	return &PostgresPaymentRepository{db: db}
}

func (r *PostgresPaymentRepository) Create(ctx context.Context, p *service.Payment) error {
	query := `
		INSERT INTO payments (id, user_id, provider, provider_tx_id, amount, currency, status, plan, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`

	_, err := r.db.ExecContext(ctx, query,
		p.ID, p.UserID, p.Provider, p.ProviderTxID,
		p.Amount, p.Currency, p.Status, p.PlanID, p.CreatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert payment: %w", err)
	}
	return nil
}

func (r *PostgresPaymentRepository) GetByProviderTx(ctx context.Context, provider, providerTxID string) (*service.Payment, error) {
	query := `SELECT id, user_id, provider, provider_tx_id, amount, currency, status, plan, created_at, confirmed_at
	           FROM payments WHERE provider = $1 AND provider_tx_id = $2`

	return r.scanPayment(r.db.QueryRowContext(ctx, query, provider, providerTxID))
}

func (r *PostgresPaymentRepository) GetByID(ctx context.Context, id string) (*service.Payment, error) {
	query := `SELECT id, user_id, provider, provider_tx_id, amount, currency, status, plan, created_at, confirmed_at
	           FROM payments WHERE id = $1`

	return r.scanPayment(r.db.QueryRowContext(ctx, query, id))
}

func (r *PostgresPaymentRepository) UpdateStatus(ctx context.Context, id, status string, confirmedAt *time.Time) error {
	query := `UPDATE payments SET status = $2, confirmed_at = $3 WHERE id = $1`

	var ct sql.NullTime
	if confirmedAt != nil {
		ct = sql.NullTime{Time: *confirmedAt, Valid: true}
	}

	result, err := r.db.ExecContext(ctx, query, id, status, ct)
	if err != nil {
		return fmt.Errorf("update payment status: %w", err)
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return service.ErrPaymentNotFound
	}
	return nil
}

func (r *PostgresPaymentRepository) scanPayment(row *sql.Row) (*service.Payment, error) {
	var p service.Payment
	var confirmedAt sql.NullTime

	err := row.Scan(&p.ID, &p.UserID, &p.Provider, &p.ProviderTxID,
		&p.Amount, &p.Currency, &p.Status, &p.PlanID, &p.CreatedAt, &confirmedAt)
	if err == sql.ErrNoRows {
		return nil, service.ErrPaymentNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan payment: %w", err)
	}

	if confirmedAt.Valid {
		p.ConfirmedAt = &confirmedAt.Time
	}
	return &p, nil
}
