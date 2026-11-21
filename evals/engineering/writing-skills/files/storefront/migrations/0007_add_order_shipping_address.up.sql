ALTER TABLE orders ADD COLUMN shipping_address_id BIGINT REFERENCES addresses (id);
