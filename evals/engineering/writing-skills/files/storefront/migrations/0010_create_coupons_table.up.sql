CREATE TABLE coupons (
    code TEXT PRIMARY KEY,
    percent_off INTEGER NOT NULL CHECK (percent_off BETWEEN 1 AND 100)
);
