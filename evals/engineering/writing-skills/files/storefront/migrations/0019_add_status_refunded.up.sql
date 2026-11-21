-- migrate: no-transaction
-- Enum values cannot be added inside a transaction.
ALTER TYPE order_status ADD VALUE 'refunded';
