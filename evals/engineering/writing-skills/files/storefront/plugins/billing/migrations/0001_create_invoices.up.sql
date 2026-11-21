CREATE TABLE invoices (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
