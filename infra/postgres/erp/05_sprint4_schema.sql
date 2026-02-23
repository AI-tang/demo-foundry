-- Sprint 4: Sourcing Scenarios – RFQ, Single-Source, MOQ Consolidation
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING

-- ────────────────────────────────────────────────────────────────────
-- 1. Extend supplier_parts with sourcing columns
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE supplier_parts ADD COLUMN IF NOT EXISTS moq INT DEFAULT 100;
ALTER TABLE supplier_parts ADD COLUMN IF NOT EXISTS capacity_per_week INT DEFAULT 5000;
ALTER TABLE supplier_parts ADD COLUMN IF NOT EXISTS last_price NUMERIC(10,2) DEFAULT 10.00;
ALTER TABLE supplier_parts ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD';
ALTER TABLE supplier_parts ADD COLUMN IF NOT EXISTS qualification_level TEXT DEFAULT 'Full';

-- Update existing supplier_parts rows with realistic values
UPDATE supplier_parts SET moq=500,  capacity_per_week=2000, last_price=12.50, currency='USD', qualification_level='Full'        WHERE supplier_id='S1' AND part_id='P1A';
UPDATE supplier_parts SET moq=200,  capacity_per_week=3000, last_price=14.80, currency='USD', qualification_level='Conditional' WHERE supplier_id='S2' AND part_id='P1A';
UPDATE supplier_parts SET moq=50,   capacity_per_week=8000, last_price=3.20,  currency='USD', qualification_level='Full'        WHERE supplier_id='S5' AND part_id='P1B';
UPDATE supplier_parts SET moq=150,  capacity_per_week=4000, last_price=8.90,  currency='USD', qualification_level='Full'        WHERE supplier_id='S3' AND part_id='P2A';
UPDATE supplier_parts SET moq=300,  capacity_per_week=10000,last_price=1.80,  currency='USD', qualification_level='Full'        WHERE supplier_id='S4' AND part_id='P2B';

-- ────────────────────────────────────────────────────────────────────
-- 2. New tables
-- ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quotes (
  rfq_id      TEXT PRIMARY KEY,
  supplier_id TEXT NOT NULL REFERENCES suppliers(supplier_id),
  part_id     TEXT NOT NULL REFERENCES parts(part_id),
  qty         INT NOT NULL,
  price       NUMERIC(10,2) NOT NULL,
  currency    TEXT NOT NULL DEFAULT 'USD',
  valid_to    DATE,
  incoterms   TEXT DEFAULT 'FOB'
);

CREATE TABLE IF NOT EXISTS transport_lanes (
  id          TEXT PRIMARY KEY,
  supplier_id TEXT NOT NULL REFERENCES suppliers(supplier_id),
  factory_id  TEXT NOT NULL,
  mode        TEXT NOT NULL,
  time_days   INT NOT NULL,
  cost        NUMERIC(10,2) NOT NULL,
  reliability NUMERIC(4,3) NOT NULL DEFAULT 0.900
);

CREATE TABLE IF NOT EXISTS demand (
  id          SERIAL PRIMARY KEY,
  order_id    TEXT NOT NULL,
  part_id     TEXT NOT NULL REFERENCES parts(part_id),
  qty         INT NOT NULL,
  need_by_date DATE NOT NULL,
  priority    INT NOT NULL DEFAULT 5,
  factory_id  TEXT NOT NULL DEFAULT 'F1'
);

-- ────────────────────────────────────────────────────────────────────
-- 3. Seed: 15 suppliers
-- ────────────────────────────────────────────────────────────────────
INSERT INTO suppliers(supplier_id, name, approved) VALUES
  ('S6',  'ShanghaiElec',    true),
  ('S7',  'GuangzhouSemi',   true),
  ('S8',  'BeijingOptics',   true),
  ('S9',  'WuhanPower',      true),
  ('S10', 'ChengduMicro',    true),
  ('S11', 'TaipeiLogic',     true),
  ('S12', 'SeoulMemory',     true),
  ('S13', 'TokyoSensor',     true),
  ('S14', 'OsakaPCB',        true),
  ('S15', 'HanoiConnect',    false)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────────
-- 4. Seed: 200+ parts using generate_series
-- ────────────────────────────────────────────────────────────────────
INSERT INTO parts(part_id, name, part_type)
SELECT 'MCU-' || lpad(i::text,3,'0'), 'MCU Chip Model ' || i, 'COMPONENT'
FROM generate_series(1,25) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'SNS-' || lpad(i::text,3,'0'), 'Sensor Module ' || i, 'COMPONENT'
FROM generate_series(1,25) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'PCB-' || lpad(i::text,3,'0'), 'PCB Board ' || i, 'COMPONENT'
FROM generate_series(1,25) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'PWR-' || lpad(i::text,3,'0'), 'Power Module ' || i, 'COMPONENT'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'CON-' || lpad(i::text,3,'0'), 'Connector ' || i, 'COMPONENT'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'CAP-' || lpad(i::text,3,'0'), 'Capacitor ' || i, 'COMPONENT'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'RES-' || lpad(i::text,3,'0'), 'Resistor ' || i, 'COMPONENT'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'IC-' || lpad(i::text,3,'0'), 'IC Chip ' || i, 'COMPONENT'
FROM generate_series(1,25) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'MEM-' || lpad(i::text,3,'0'), 'Memory Module ' || i, 'COMPONENT'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO parts(part_id, name, part_type)
SELECT 'DSP-' || lpad(i::text,3,'0'), 'Display Module ' || i, 'COMPONENT'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────────
-- 5. Seed: supplier_parts (many-to-many with sourcing attributes)
--    Each supplier supplies parts in their specialty categories.
--    Bottleneck parts (MCU-001, IC-001, CAP-001) have limited sources.
-- ────────────────────────────────────────────────────────────────────

-- S1 TaiwanChipCo → MCU (1-15), IC (1-10) — primary MCU supplier
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S1', 'MCU-' || lpad(i::text,3,'0'), 1, 12 + (i % 5), 500, 2000 + (i*100), round((10 + random()*5)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S1', 'IC-' || lpad(i::text,3,'0'), 2, 14 + (i % 4), 300, 1500 + (i*80), round((8 + random()*4)::numeric,2), 'USD', 'Full'
FROM generate_series(1,10) AS i ON CONFLICT DO NOTHING;

-- S2 KoreaChipBackup → MCU (1-10), IC (1-8) — backup, slightly cheaper
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S2', 'MCU-' || lpad(i::text,3,'0'), 2, 10 + (i % 3), 200, 3000, round((9 + random()*4)::numeric,2), 'USD', 'Conditional'
FROM generate_series(1,10) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S2', 'IC-' || lpad(i::text,3,'0'), 2, 11 + (i % 3), 250, 2500, round((7.5 + random()*3)::numeric,2), 'USD', 'Conditional'
FROM generate_series(1,8) AS i ON CONFLICT DO NOTHING;

-- S3 JapanSensor → SNS (1-20)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S3', 'SNS-' || lpad(i::text,3,'0'), 1, 10 + (i % 6), 100, 4000, round((6 + random()*3)::numeric,2), 'USD', 'Full'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

-- S4 SuzhouPCB → PCB (1-25)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S4', 'PCB-' || lpad(i::text,3,'0'), 1, 5 + (i % 4), 300, 10000, round((1.5 + random()*1.5)::numeric,2), 'USD', 'Full'
FROM generate_series(1,25) AS i ON CONFLICT DO NOTHING;

-- S5 ShenzhenPower → PWR (1-20)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S5', 'PWR-' || lpad(i::text,3,'0'), 1, 7 + (i % 5), 50, 8000, round((3 + random()*2)::numeric,2), 'USD', 'Full'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

-- S6 ShanghaiElec → CON (1-15), CAP (1-15)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S6', 'CON-' || lpad(i::text,3,'0'), 1, 6 + (i % 4), 200, 6000, round((0.8 + random()*0.6)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S6', 'CAP-' || lpad(i::text,3,'0'), 1, 5 + (i % 3), 1000, 20000, round((0.05 + random()*0.1)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

-- S7 GuangzhouSemi → MCU (16-25), IC (11-20), MEM (1-10)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S7', 'MCU-' || lpad(i::text,3,'0'), 1, 11 + (i % 4), 400, 2500, round((11 + random()*4)::numeric,2), 'USD', 'Full'
FROM generate_series(16,25) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S7', 'IC-' || lpad(i::text,3,'0'), 1, 13 + (i % 5), 350, 2000, round((9 + random()*3)::numeric,2), 'USD', 'Full'
FROM generate_series(11,20) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S7', 'MEM-' || lpad(i::text,3,'0'), 1, 15 + (i % 3), 200, 3000, round((18 + random()*6)::numeric,2), 'USD', 'Full'
FROM generate_series(1,10) AS i ON CONFLICT DO NOTHING;

-- S8 BeijingOptics → DSP (1-15), SNS (16-25)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S8', 'DSP-' || lpad(i::text,3,'0'), 1, 14 + (i % 5), 100, 2000, round((22 + random()*8)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S8', 'SNS-' || lpad(i::text,3,'0'), 2, 12 + (i % 4), 150, 3000, round((7 + random()*2)::numeric,2), 'USD', 'Conditional'
FROM generate_series(16,25) AS i ON CONFLICT DO NOTHING;

-- S9 WuhanPower → PWR (5-20 backup), CAP (10-20)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S9', 'PWR-' || lpad(i::text,3,'0'), 2, 9 + (i % 4), 100, 5000, round((3.5 + random()*2)::numeric,2), 'USD', 'Full'
FROM generate_series(5,20) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S9', 'CAP-' || lpad(i::text,3,'0'), 2, 6 + (i % 3), 800, 15000, round((0.06 + random()*0.08)::numeric,2), 'USD', 'Full'
FROM generate_series(10,20) AS i ON CONFLICT DO NOTHING;

-- S10 ChengduMicro → MCU (5-15 backup), RES (1-20)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S10', 'MCU-' || lpad(i::text,3,'0'), 3, 15 + (i % 5), 600, 1500, round((13 + random()*5)::numeric,2), 'USD', 'Pending'
FROM generate_series(5,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S10', 'RES-' || lpad(i::text,3,'0'), 1, 4 + (i % 3), 2000, 50000, round((0.02 + random()*0.03)::numeric,2), 'USD', 'Full'
FROM generate_series(1,20) AS i ON CONFLICT DO NOTHING;

-- S11 TaipeiLogic → IC (1-15), MEM (5-15)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S11', 'IC-' || lpad(i::text,3,'0'), 1, 12 + (i % 4), 250, 3000, round((8 + random()*4)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S11', 'MEM-' || lpad(i::text,3,'0'), 2, 14 + (i % 3), 150, 2500, round((19 + random()*5)::numeric,2), 'USD', 'Full'
FROM generate_series(5,15) AS i ON CONFLICT DO NOTHING;

-- S12 SeoulMemory → MEM (1-15), IC (15-25)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S12', 'MEM-' || lpad(i::text,3,'0'), 1, 13 + (i % 4), 100, 4000, round((17 + random()*5)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S12', 'IC-' || lpad(i::text,3,'0'), 2, 15 + (i % 3), 300, 1800, round((9.5 + random()*3)::numeric,2), 'USD', 'Conditional'
FROM generate_series(15,25) AS i ON CONFLICT DO NOTHING;

-- S13 TokyoSensor → SNS (1-15 backup), DSP (5-15 backup)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S13', 'SNS-' || lpad(i::text,3,'0'), 2, 11 + (i % 4), 120, 3500, round((6.5 + random()*2.5)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S13', 'DSP-' || lpad(i::text,3,'0'), 2, 16 + (i % 5), 80, 1500, round((24 + random()*6)::numeric,2), 'USD', 'Conditional'
FROM generate_series(5,15) AS i ON CONFLICT DO NOTHING;

-- S14 OsakaPCB → PCB (1-15 backup), CON (10-20)
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S14', 'PCB-' || lpad(i::text,3,'0'), 2, 7 + (i % 4), 250, 8000, round((1.8 + random()*1)::numeric,2), 'USD', 'Full'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S14', 'CON-' || lpad(i::text,3,'0'), 2, 8 + (i % 3), 300, 5000, round((0.9 + random()*0.5)::numeric,2), 'USD', 'Full'
FROM generate_series(10,20) AS i ON CONFLICT DO NOTHING;

-- S15 HanoiConnect → CON (1-10), RES (10-20)  — NOT approved!
INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S15', 'CON-' || lpad(i::text,3,'0'), 3, 10 + (i % 4), 500, 7000, round((0.5 + random()*0.3)::numeric,2), 'USD', 'Pending'
FROM generate_series(1,10) AS i ON CONFLICT DO NOTHING;

INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days, moq, capacity_per_week, last_price, currency, qualification_level)
SELECT 'S15', 'RES-' || lpad(i::text,3,'0'), 3, 8 + (i % 3), 3000, 40000, round((0.015 + random()*0.02)::numeric,2), 'USD', 'Pending'
FROM generate_series(10,20) AS i ON CONFLICT DO NOTHING;

-- *** Bottleneck parts: MCU-001 has ONLY S1 (single-source) ***
-- MCU-001 is only supplied by S1 (no S2, no S7, no S10 — they start at MCU-005+)
-- IC-001 supplied by S1 + S2 + S11 (3 sources, but S2 is Conditional)
-- CAP-001 supplied by ONLY S6 (single-source)

-- Ensure P1A also supplied by existing rows only (S1 + S2)
-- Ensure some parts only have ONE supplier:
-- DSP-001 to DSP-004: only S8 (single-source displays)
-- SNS-021 to SNS-025: only S8 (Conditional, risky)

-- ────────────────────────────────────────────────────────────────────
-- 6. Seed: transport_lanes
-- ────────────────────────────────────────────────────────────────────
INSERT INTO transport_lanes(id, supplier_id, factory_id, mode, time_days, cost, reliability) VALUES
  -- S1 lanes
  ('TL-S1-F1-Ocean','S1','F1','Ocean',21,0.50,0.920),
  ('TL-S1-F1-Air',  'S1','F1','Air',   3,4.80,0.980),
  ('TL-S1-F2-Ocean','S1','F2','Ocean',25,0.60,0.880),
  ('TL-S1-F2-Air',  'S1','F2','Air',   4,5.20,0.960),
  ('TL-S1-F3-Ocean','S1','F3','Ocean',18,0.55,0.900),
  ('TL-S1-F3-Air',  'S1','F3','Air',   4,5.00,0.970),
  -- S2 lanes
  ('TL-S2-F1-Ocean','S2','F1','Ocean',14,0.60,0.900),
  ('TL-S2-F1-Air',  'S2','F1','Air',   2,5.20,0.970),
  ('TL-S2-F3-Ocean','S2','F3','Ocean',12,0.65,0.910),
  ('TL-S2-F3-Air',  'S2','F3','Air',   3,5.50,0.950),
  -- S3 lanes
  ('TL-S3-F1-Ocean','S3','F1','Ocean',18,0.45,0.930),
  ('TL-S3-F1-Air',  'S3','F1','Air',   3,4.50,0.980),
  ('TL-S3-F2-Ocean','S3','F2','Ocean',20,0.55,0.900),
  -- S4 lanes
  ('TL-S4-F1-Truck','S4','F1','Truck',  2,0.30,0.950),
  ('TL-S4-F1-Air',  'S4','F1','Air',    1,3.00,0.990),
  ('TL-S4-F2-Truck','S4','F2','Truck',  3,0.35,0.940),
  -- S5 lanes
  ('TL-S5-F1-Truck','S5','F1','Truck',  1,0.25,0.960),
  ('TL-S5-F1-Air',  'S5','F1','Air',    1,2.50,0.990),
  ('TL-S5-F2-Truck','S5','F2','Truck',  2,0.30,0.950),
  -- S6 lanes
  ('TL-S6-F1-Truck','S6','F1','Truck',  2,0.20,0.950),
  ('TL-S6-F1-Air',  'S6','F1','Air',    1,2.00,0.980),
  ('TL-S6-F2-Truck','S6','F2','Truck',  3,0.28,0.940),
  -- S7 lanes
  ('TL-S7-F1-Truck','S7','F1','Truck',  3,0.35,0.930),
  ('TL-S7-F1-Air',  'S7','F1','Air',    1,3.50,0.970),
  ('TL-S7-F2-Truck','S7','F2','Truck',  4,0.40,0.920),
  -- S8 lanes
  ('TL-S8-F1-Rail', 'S8','F1','Rail',   5,0.80,0.910),
  ('TL-S8-F1-Air',  'S8','F1','Air',    2,4.00,0.970),
  -- S9 lanes
  ('TL-S9-F1-Rail', 'S9','F1','Rail',   4,0.70,0.920),
  ('TL-S9-F1-Air',  'S9','F1','Air',    2,3.80,0.960),
  ('TL-S9-F2-Rail', 'S9','F2','Rail',   5,0.85,0.900),
  -- S10 lanes
  ('TL-S10-F1-Rail','S10','F1','Rail',   6,0.90,0.900),
  ('TL-S10-F1-Air', 'S10','F1','Air',    2,4.20,0.960),
  -- S11 lanes
  ('TL-S11-F1-Ocean','S11','F1','Ocean',10,0.55,0.920),
  ('TL-S11-F1-Air',  'S11','F1','Air',   2,5.00,0.970),
  ('TL-S11-F3-Ocean','S11','F3','Ocean', 8,0.50,0.930),
  -- S12 lanes
  ('TL-S12-F1-Ocean','S12','F1','Ocean',12,0.58,0.910),
  ('TL-S12-F1-Air',  'S12','F1','Air',   2,5.50,0.960),
  -- S13 lanes
  ('TL-S13-F1-Ocean','S13','F1','Ocean',16,0.48,0.920),
  ('TL-S13-F1-Air',  'S13','F1','Air',   3,4.60,0.970),
  -- S14 lanes
  ('TL-S14-F1-Ocean','S14','F1','Ocean',14,0.52,0.910),
  ('TL-S14-F1-Air',  'S14','F1','Air',   3,4.80,0.960),
  -- S15 lanes
  ('TL-S15-F1-Ocean','S15','F1','Ocean',20,0.42,0.870),
  ('TL-S15-F1-Air',  'S15','F1','Air',   4,3.20,0.940)
ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────────
-- 7. Seed: 120 demand records across factories
--    Bottleneck: MCU-001 needed by 12 orders, IC-001 by 10, CAP-001 by 8
-- ────────────────────────────────────────────────────────────────────

-- Bottleneck MCU-001: 12 orders need it
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (1100 + i), 'MCU-001', 200 + (i * 50), CURRENT_DATE + (10 + i*2) * INTERVAL '1 day', 1 + (i % 3), CASE WHEN i <= 6 THEN 'F1' WHEN i <= 9 THEN 'F2' ELSE 'F3' END
FROM generate_series(1,12) AS i ON CONFLICT DO NOTHING;

-- Bottleneck IC-001: 10 orders
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (1200 + i), 'IC-001', 150 + (i * 30), CURRENT_DATE + (8 + i*3) * INTERVAL '1 day', 1 + (i % 4), CASE WHEN i <= 5 THEN 'F1' ELSE 'F2' END
FROM generate_series(1,10) AS i ON CONFLICT DO NOTHING;

-- Bottleneck CAP-001: 8 orders
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (1300 + i), 'CAP-001', 5000 + (i * 1000), CURRENT_DATE + (7 + i*2) * INTERVAL '1 day', 2, 'F1'
FROM generate_series(1,8) AS i ON CONFLICT DO NOTHING;

-- P1A demand (existing bottleneck)
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (1400 + i), 'P1A', 300 + (i * 100), CURRENT_DATE + (12 + i*2) * INTERVAL '1 day', 1 + (i % 3), CASE WHEN i <= 4 THEN 'F1' ELSE 'F3' END
FROM generate_series(1,8) AS i ON CONFLICT DO NOTHING;

-- MCU parts demand (various)
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2000 + i), 'MCU-' || lpad((1 + (i % 25))::text,3,'0'), 100 + (i * 20), CURRENT_DATE + (10 + (i % 30)) * INTERVAL '1 day', 1 + (i % 5), CASE WHEN i % 3 = 0 THEN 'F1' WHEN i % 3 = 1 THEN 'F2' ELSE 'F3' END
FROM generate_series(1,25) AS i ON CONFLICT DO NOTHING;

-- Sensor parts demand
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2100 + i), 'SNS-' || lpad((1 + (i % 20))::text,3,'0'), 80 + (i * 15), CURRENT_DATE + (8 + (i % 25)) * INTERVAL '1 day', 2 + (i % 4), CASE WHEN i % 2 = 0 THEN 'F1' ELSE 'F2' END
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

-- PCB parts demand
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2200 + i), 'PCB-' || lpad((1 + (i % 20))::text,3,'0'), 500 + (i * 100), CURRENT_DATE + (5 + (i % 20)) * INTERVAL '1 day', 1 + (i % 3), 'F1'
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

-- IC parts demand
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2300 + i), 'IC-' || lpad((1 + (i % 20))::text,3,'0'), 120 + (i * 25), CURRENT_DATE + (12 + (i % 28)) * INTERVAL '1 day', 1 + (i % 4), CASE WHEN i % 2 = 0 THEN 'F1' ELSE 'F3' END
FROM generate_series(1,15) AS i ON CONFLICT DO NOTHING;

-- Power / connector / memory / display demand
INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2400 + i), 'PWR-' || lpad((1 + (i % 15))::text,3,'0'), 50 + (i * 10), CURRENT_DATE + (10 + (i % 20)) * INTERVAL '1 day', 3, 'F1'
FROM generate_series(1,10) AS i ON CONFLICT DO NOTHING;

INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2500 + i), 'MEM-' || lpad((1 + (i % 12))::text,3,'0'), 60 + (i * 20), CURRENT_DATE + (15 + (i % 25)) * INTERVAL '1 day', 2, 'F1'
FROM generate_series(1,8) AS i ON CONFLICT DO NOTHING;

INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2600 + i), 'DSP-' || lpad((1 + (i % 10))::text,3,'0'), 30 + (i * 5), CURRENT_DATE + (18 + (i % 22)) * INTERVAL '1 day', 2, 'F2'
FROM generate_series(1,6) AS i ON CONFLICT DO NOTHING;

INSERT INTO demand(order_id, part_id, qty, need_by_date, priority, factory_id)
SELECT 'SO' || (2700 + i), 'CON-' || lpad((1 + (i % 15))::text,3,'0'), 400 + (i * 50), CURRENT_DATE + (6 + (i % 18)) * INTERVAL '1 day', 3, 'F1'
FROM generate_series(1,8) AS i ON CONFLICT DO NOTHING;

-- ────────────────────────────────────────────────────────────────────
-- 8. Seed: sample quotes (RFQs)
-- ────────────────────────────────────────────────────────────────────
INSERT INTO quotes(rfq_id, supplier_id, part_id, qty, price, currency, valid_to, incoterms) VALUES
  ('RFQ-001','S1','MCU-001',1000,11.50,'USD',CURRENT_DATE + INTERVAL '30 days','FOB'),
  ('RFQ-002','S2','MCU-001',1000,10.80,'USD',CURRENT_DATE + INTERVAL '30 days','FOB'),
  ('RFQ-003','S1','P1A',    500, 12.00,'USD',CURRENT_DATE + INTERVAL '20 days','FOB'),
  ('RFQ-004','S2','P1A',    500, 14.50,'USD',CURRENT_DATE + INTERVAL '20 days','CIF'),
  ('RFQ-005','S3','SNS-001',2000, 5.80,'USD',CURRENT_DATE + INTERVAL '45 days','FOB'),
  ('RFQ-006','S13','SNS-001',2000,6.20,'USD',CURRENT_DATE + INTERVAL '45 days','FOB'),
  ('RFQ-007','S4','PCB-001',5000, 1.50,'USD',CURRENT_DATE + INTERVAL '60 days','EXW'),
  ('RFQ-008','S14','PCB-001',5000,1.75,'USD',CURRENT_DATE + INTERVAL '60 days','FOB'),
  ('RFQ-009','S6','CAP-001',20000,0.05,'USD',CURRENT_DATE + INTERVAL '30 days','FOB'),
  ('RFQ-010','S11','IC-001', 800, 8.20,'USD',CURRENT_DATE + INTERVAL '25 days','CIF'),
  ('RFQ-011','S1','IC-001',  800, 8.80,'USD',CURRENT_DATE + INTERVAL '25 days','FOB'),
  ('RFQ-012','S12','MEM-001',500,17.50,'USD',CURRENT_DATE + INTERVAL '35 days','FOB'),
  ('RFQ-013','S7','MEM-001', 500,18.90,'USD',CURRENT_DATE + INTERVAL '35 days','FOB'),
  ('RFQ-014','S5','PWR-001',1000, 3.10,'USD',CURRENT_DATE + INTERVAL '40 days','FOB'),
  ('RFQ-015','S9','PWR-005',1000, 3.80,'USD',CURRENT_DATE + INTERVAL '40 days','FOB'),
  ('RFQ-016','S8','DSP-001', 200,22.50,'USD',CURRENT_DATE + INTERVAL '30 days','CIF'),
  ('RFQ-017','S10','MCU-005',800,14.20,'USD',CURRENT_DATE + INTERVAL '25 days','FOB'),
  ('RFQ-018','S1','MCU-005', 800,11.80,'USD',CURRENT_DATE + INTERVAL '25 days','FOB'),
  ('RFQ-019','S6','CON-001',3000, 0.82,'USD',CURRENT_DATE + INTERVAL '30 days','EXW'),
  ('RFQ-020','S14','CON-010',3000,0.95,'USD',CURRENT_DATE + INTERVAL '30 days','FOB')
ON CONFLICT DO NOTHING;
