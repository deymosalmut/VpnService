-- VPN Service — User Management schema
-- This runs automatically on first postgres startup

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id     VARCHAR(255) NOT NULL,          -- telegram_id or email
    source          VARCHAR(50)  NOT NULL,           -- 'telegram' | 'email'
    status          VARCHAR(50)  NOT NULL DEFAULT 'pending',  -- pending | active | expired | disabled
    plan            VARCHAR(50),                     -- '30d' | '90d' | '365d'
    subscription_url TEXT,                           -- Marzban subscription URL
    marzban_username VARCHAR(255),                   -- username in Marzban
    activated_at    TIMESTAMP WITH TIME ZONE,
    paid_at         TIMESTAMP WITH TIME ZONE,
    expires_at      TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(external_id, source)
);

-- Payment history
CREATE TABLE IF NOT EXISTS payments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider        VARCHAR(50)  NOT NULL,           -- 'sbp' | 'cryptomus'
    provider_tx_id  VARCHAR(255),                    -- external transaction ID
    amount          DECIMAL(10,2) NOT NULL,
    currency        VARCHAR(10)  NOT NULL DEFAULT 'RUB',
    status          VARCHAR(50)  NOT NULL DEFAULT 'pending',  -- pending | confirmed | failed | refunded
    plan            VARCHAR(50)  NOT NULL,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    confirmed_at    TIMESTAMP WITH TIME ZONE
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_users_external    ON users(external_id, source);
CREATE INDEX IF NOT EXISTS idx_users_status       ON users(status);
CREATE INDEX IF NOT EXISTS idx_users_expires      ON users(expires_at);
CREATE INDEX IF NOT EXISTS idx_payments_user      ON payments(user_id);
CREATE INDEX IF NOT EXISTS idx_payments_provider  ON payments(provider, provider_tx_id);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
