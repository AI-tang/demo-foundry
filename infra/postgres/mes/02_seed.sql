INSERT INTO factories(factory_id, name) VALUES
  ('F1','Shanghai Plant'),
  ('F2','Suzhou Plant'),
  ('F3','Chongqing Backup Plant')
ON CONFLICT DO NOTHING;

INSERT INTO machines(machine_id, factory_id, status, capacity_per_day) VALUES
  ('M1','F1','Running',1000),
  ('M2','F3','Idle',800)
ON CONFLICT DO NOTHING;

INSERT INTO production_orders(prod_order_id, sales_order_id, factory_id, product_id, qty, status, planned_start, planned_end, updated_at) VALUES
  ('MO5001','SO1001','F1','PR1',1000,'Scheduled','2026-02-15','2026-02-20', now())
ON CONFLICT DO NOTHING;

INSERT INTO work_orders(work_order_id, prod_order_id, machine_id, status, updated_at) VALUES
  ('WO6001','MO5001','M1','NotReleased', now())
ON CONFLICT DO NOTHING;
