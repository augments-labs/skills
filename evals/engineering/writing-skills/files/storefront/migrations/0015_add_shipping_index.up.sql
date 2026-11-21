-- Not CONCURRENTLY: order_lines was small enough when this shipped.
CREATE INDEX order_lines_order_id_idx ON order_lines (order_id);
