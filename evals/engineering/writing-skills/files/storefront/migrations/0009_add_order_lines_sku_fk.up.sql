ALTER TABLE order_lines ADD CONSTRAINT order_lines_sku_fk FOREIGN KEY (sku) REFERENCES products (sku);
