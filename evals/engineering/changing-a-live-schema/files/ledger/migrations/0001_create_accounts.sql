CREATE TABLE accounts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name text NOT NULL,
    plan text NOT NULL DEFAULT 'free',
    created_at timestamptz NOT NULL DEFAULT now()
);
