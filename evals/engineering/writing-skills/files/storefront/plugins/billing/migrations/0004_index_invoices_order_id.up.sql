-- migrate: no-transaction
CREATE INDEX CONCURRENTLY invoices_order_id_idx ON invoices (order_id);
