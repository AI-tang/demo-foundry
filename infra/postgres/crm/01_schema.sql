CREATE TABLE IF NOT EXISTS customers (
  customer_id TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS crm_orders (
  crm_order_id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL REFERENCES customers(customer_id),
  order_date DATE NOT NULL,
  status TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);
