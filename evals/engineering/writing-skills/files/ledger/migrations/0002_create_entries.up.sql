CREATE TABLE entries (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts (id),
    amount_cents BIGINT NOT NULL,
    posted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
