CREATE TABLE IF NOT EXISTS suppliers (
  supplier_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  approved BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS parts (
  part_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  part_type TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS supplier_parts (
  supplier_id TEXT NOT NULL REFERENCES suppliers(supplier_id),
  part_id TEXT NOT NULL REFERENCES parts(part_id),
  priority INT NOT NULL DEFAULT 1,
  lead_time_days INT NOT NULL DEFAULT 7,
  PRIMARY KEY (supplier_id, part_id)
);

CREATE TABLE IF NOT EXISTS purchase_orders (
  po_id TEXT PRIMARY KEY,
  part_id TEXT NOT NULL REFERENCES parts(part_id),
  supplier_id TEXT NOT NULL REFERENCES suppliers(supplier_id),
  qty INT NOT NULL,
  status TEXT NOT NULL,
  eta DATE,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS shipments (
  shipment_id TEXT PRIMARY KEY,
  po_id TEXT NOT NULL REFERENCES purchase_orders(po_id),
  mode TEXT NOT NULL,
  status TEXT NOT NULL,
  eta DATE,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory_lots (
  lot_id TEXT PRIMARY KEY,
  part_id TEXT NOT NULL REFERENCES parts(part_id),
  on_hand INT NOT NULL,
  reserved INT NOT NULL DEFAULT 0,
  location TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);
