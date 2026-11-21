-- migrate: no-transaction
CREATE INDEX CONCURRENTLY refunds_order_id_idx ON refunds (order_id);
