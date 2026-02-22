CREATE TABLE IF NOT EXISTS factories (
  factory_id TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS machines (
  machine_id TEXT PRIMARY KEY,
  factory_id TEXT NOT NULL REFERENCES factories(factory_id),
  status TEXT NOT NULL,
  capacity_per_day INT NOT NULL
);

CREATE TABLE IF NOT EXISTS production_orders (
  prod_order_id TEXT PRIMARY KEY,
  sales_order_id TEXT NOT NULL,
  factory_id TEXT NOT NULL REFERENCES factories(factory_id),
  product_id TEXT NOT NULL,
  qty INT NOT NULL,
  status TEXT NOT NULL,
  planned_start DATE,
  planned_end DATE,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS work_orders (
  work_order_id TEXT PRIMARY KEY,
  prod_order_id TEXT NOT NULL REFERENCES production_orders(prod_order_id),
  machine_id TEXT NOT NULL REFERENCES machines(machine_id),
  status TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);
