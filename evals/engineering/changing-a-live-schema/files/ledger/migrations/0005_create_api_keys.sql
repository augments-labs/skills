CREATE TABLE api_keys (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id bigint NOT NULL REFERENCES accounts (id),
    hashed_key text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);
