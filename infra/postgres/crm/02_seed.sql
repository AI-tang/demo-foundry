INSERT INTO customers(customer_id, name) VALUES
  ('CUST1','Airbus-like Customer'),
  ('CUST2','Tier-1 OEM')
ON CONFLICT DO NOTHING;

INSERT INTO crm_orders(crm_order_id, customer_id, order_date, status, updated_at) VALUES
  ('SO1001','CUST1','2026-02-01','Confirmed', now()),
  ('SO1002','CUST1','2026-02-03','Confirmed', now())
ON CONFLICT DO NOTHING;
