INSERT INTO suppliers(supplier_id, name, approved) VALUES
  ('S1','TaiwanChipCo', true),
  ('S2','KoreaChipBackup', true),
  ('S3','JapanSensor', true),
  ('S4','SuzhouPCB', true),
  ('S5','ShenzhenPower', true)
ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type) VALUES
  ('PR1','Smart Control System','PRODUCT'),
  ('P1','MainBoard','ASSEMBLY'),
  ('P1A','MCU Chip','COMPONENT'),
  ('P1B','Power Module','COMPONENT'),
  ('P2','Sensor Module','ASSEMBLY'),
  ('P2A','Sensor Chip','COMPONENT'),
  ('P2B','PCB Board','COMPONENT'),
  ('P3','Housing','COMPONENT')
ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days) VALUES
  ('S1','P1A',1,14),
  ('S2','P1A',2,10),
  ('S5','P1B',1,7),
  ('S3','P2A',1,12),
  ('S4','P2B',1,5)
ON CONFLICT DO NOTHING;

INSERT INTO purchase_orders(po_id, part_id, supplier_id, qty, status, eta, updated_at) VALUES
  ('PO-ERP-2001','P1A','S1',1000,'Open','2026-02-18', now()),
  ('PO-ERP-2002','P2B','S4',1200,'QC_Hold','2026-02-14', now())
ON CONFLICT DO NOTHING;

INSERT INTO shipments(shipment_id, po_id, mode, status, eta, updated_at) VALUES
  ('SHIP-3001','PO-ERP-2001','Ocean','InTransit','2026-02-18', now()),
  ('SHIP-3002','PO-ERP-2002','Truck','Arrived','2026-02-14', now())
ON CONFLICT DO NOTHING;

INSERT INTO inventory_lots(lot_id, part_id, on_hand, reserved, location, updated_at) VALUES
  ('LOT-4001','P1A',200,150,'F1-WH', now()),
  ('LOT-4002','P2B',800,0,'F2-WH', now())
ON CONFLICT DO NOTHING;
