package repository

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/lib/pq"

	"github.com/your-org/vpn-service/user-mgmt/internal/service"
)

// PostgresUserRepository implements service.UserRepository using PostgreSQL.
type PostgresUserRepository struct {
	db *sql.DB
}

func NewPostgresUserRepository(db *sql.DB) *PostgresUserRepository {
	return &PostgresUserRepository{db: db}
}

// ConnectPostgres creates a new PostgreSQL connection with retry.
func ConnectPostgres(dsn string, maxRetries int) (*sql.DB, error) {
	var db *sql.DB
	var err error

	for i := 0; i < maxRetries; i++ {
		db, err = sql.Open("postgres", dsn)
		if err != nil {
			time.Sleep(time.Duration(i+1) * time.Second)
			continue
		}

		if err = db.Ping(); err != nil {
			time.Sleep(time.Duration(i+1) * time.Second)
			continue
		}

		db.SetMaxOpenConns(25)
		db.SetMaxIdleConns(5)
		db.SetConnMaxLifetime(5 * time.Minute)
		return db, nil
	}

	return nil, fmt.Errorf("postgres connect failed after %d retries: %w", maxRetries, err)
}

func (r *PostgresUserRepository) Create(ctx context.Context, user *service.User) error {
	query := `
		INSERT INTO users (id, external_id, source, status, plan, subscription_url, marzban_username,
		                    activated_at, paid_at, expires_at, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		ON CONFLICT (external_id, source) DO UPDATE SET
			status = EXCLUDED.status,
			plan = COALESCE(EXCLUDED.plan, users.plan),
			activated_at = COALESCE(EXCLUDED.activated_at, users.activated_at),
			paid_at = COALESCE(EXCLUDED.paid_at, users.paid_at),
			updated_at = NOW()
		RETURNING id`

	return r.db.QueryRowContext(ctx, query,
		user.ID, user.ExternalID, user.Source, user.Status, user.Plan,
		nullString(user.SubscriptionURL), nullString(user.MarzbanUsername),
		nullTime(user.ActivatedAt), nullTime(user.PaidAt), nullTime(user.ExpiresAt),
		user.CreatedAt, user.UpdatedAt,
	).Scan(&user.ID)
}

func (r *PostgresUserRepository) GetByExternalID(ctx context.Context, externalID, source string) (*service.User, error) {
	query := `SELECT id, external_id, source, status, plan, subscription_url, marzban_username,
	                  activated_at, paid_at, expires_at, created_at, updated_at
	           FROM users WHERE external_id = $1`
	args := []interface{}{externalID}

	if source != "" {
		query += " AND source = $2"
		args = append(args, source)
	}
	query += " LIMIT 1"

	return r.scanUser(r.db.QueryRowContext(ctx, query, args...))
}

func (r *PostgresUserRepository) GetByID(ctx context.Context, id string) (*service.User, error) {
	query := `SELECT id, external_id, source, status, plan, subscription_url, marzban_username,
	                  activated_at, paid_at, expires_at, created_at, updated_at
	           FROM users WHERE id = $1`
	return r.scanUser(r.db.QueryRowContext(ctx, query, id))
}

func (r *PostgresUserRepository) Update(ctx context.Context, user *service.User) error {
	query := `
		UPDATE users SET
			status = $2, plan = $3, subscription_url = $4, marzban_username = $5,
			activated_at = $6, paid_at = $7, expires_at = $8, updated_at = NOW()
		WHERE id = $1`

	result, err := r.db.ExecContext(ctx, query,
		user.ID, user.Status, user.Plan,
		nullString(user.SubscriptionURL), nullString(user.MarzbanUsername),
		nullTime(user.ActivatedAt), nullTime(user.PaidAt), nullTime(user.ExpiresAt),
	)
	if err != nil {
		return fmt.Errorf("update user: %w", err)
	}

	rows, _ := result.RowsAffected()
	if rows == 0 {
		return service.ErrUserNotFound
	}
	return nil
}

func (r *PostgresUserRepository) ListExpiring(ctx context.Context, before time.Time) ([]*service.User, error) {
	query := `SELECT id, external_id, source, status, plan, subscription_url, marzban_username,
	                  activated_at, paid_at, expires_at, created_at, updated_at
	           FROM users
	           WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at < $1
	           ORDER BY expires_at ASC`

	rows, err := r.db.QueryContext(ctx, query, before)
	if err != nil {
		return nil, fmt.Errorf("list expiring: %w", err)
	}
	defer rows.Close()

	var users []*service.User
	for rows.Next() {
		u, err := r.scanUserFromRows(rows)
		if err != nil {
			return nil, err
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

func (r *PostgresUserRepository) scanUser(row *sql.Row) (*service.User, error) {
	var u service.User
	var subURL, mzUser sql.NullString
	var activatedAt, paidAt, expiresAt sql.NullTime

	err := row.Scan(&u.ID, &u.ExternalID, &u.Source, &u.Status, &u.Plan,
		&subURL, &mzUser, &activatedAt, &paidAt, &expiresAt, &u.CreatedAt, &u.UpdatedAt)
	if err == sql.ErrNoRows {
		return nil, service.ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan user: %w", err)
	}

	u.SubscriptionURL = subURL.String
	u.MarzbanUsername = mzUser.String
	if activatedAt.Valid {
		u.ActivatedAt = &activatedAt.Time
	}
	if paidAt.Valid {
		u.PaidAt = &paidAt.Time
	}
	if expiresAt.Valid {
		u.ExpiresAt = &expiresAt.Time
	}
	return &u, nil
}

func (r *PostgresUserRepository) scanUserFromRows(rows *sql.Rows) (*service.User, error) {
	var u service.User
	var subURL, mzUser sql.NullString
	var activatedAt, paidAt, expiresAt sql.NullTime

	err := rows.Scan(&u.ID, &u.ExternalID, &u.Source, &u.Status, &u.Plan,
		&subURL, &mzUser, &activatedAt, &paidAt, &expiresAt, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("scan user row: %w", err)
	}

	u.SubscriptionURL = subURL.String
	u.MarzbanUsername = mzUser.String
	if activatedAt.Valid {
		u.ActivatedAt = &activatedAt.Time
	}
	if paidAt.Valid {
		u.PaidAt = &paidAt.Time
	}
	if expiresAt.Valid {
		u.ExpiresAt = &expiresAt.Time
	}
	return &u, nil
}

func nullString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

func nullTime(t *time.Time) sql.NullTime {
	if t == nil {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: *t, Valid: true}
}
