// Sprint 2 — What-if Twin-Sim data extensions
// Runs AFTER seed.cypher / seed_generated.cypher (additive, uses MERGE)

// ── Ensure core demo nodes exist (may have been overwritten by generated seed) ──

MERGE (p1a:Part {id:'P1A'}) SET p1a.name = 'MCU Chip', p1a.partType = 'COMPONENT';
MERGE (p1b:Part {id:'P1B'}) SET p1b.name = 'Power Module', p1b.partType = 'COMPONENT';
MERGE (p2a:Part {id:'P2A'}) SET p2a.name = 'Sensor Chip', p2a.partType = 'COMPONENT';
MERGE (p2b:Part {id:'P2B'}) SET p2b.name = 'PCB Board', p2b.partType = 'COMPONENT';
MERGE (p1:Part  {id:'P1'})  SET p1.name  = 'MainBoard',  p1.partType  = 'ASSEMBLY';
MERGE (p2:Part  {id:'P2'})  SET p2.name  = 'Sensor Module', p2.partType = 'ASSEMBLY';
MERGE (p3:Part  {id:'P3'})  SET p3.name  = 'Housing', p3.partType = 'COMPONENT';

MERGE (pr1:Product {id:'PR1'}) SET pr1.name = 'Smart Control System';

// BOM links
MATCH (pr1:Product {id:'PR1'}), (p1:Part {id:'P1'})  MERGE (pr1)-[:HAS_COMPONENT]->(p1);
MATCH (pr1:Product {id:'PR1'}), (p2:Part {id:'P2'})  MERGE (pr1)-[:HAS_COMPONENT]->(p2);
MATCH (pr1:Product {id:'PR1'}), (p3:Part {id:'P3'})  MERGE (pr1)-[:HAS_COMPONENT]->(p3);
MATCH (p1:Part {id:'P1'}), (p1a:Part {id:'P1A'})     MERGE (p1)-[:HAS_COMPONENT]->(p1a);
MATCH (p1:Part {id:'P1'}), (p1b:Part {id:'P1B'})     MERGE (p1)-[:HAS_COMPONENT]->(p1b);
MATCH (p2:Part {id:'P2'}), (p2a:Part {id:'P2A'})     MERGE (p2)-[:HAS_COMPONENT]->(p2a);
MATCH (p2:Part {id:'P2'}), (p2b:Part {id:'P2B'})     MERGE (p2)-[:HAS_COMPONENT]->(p2b);

// Factory produces
MATCH (f1:Factory {id:'F1'}), (pr1:Product {id:'PR1'}) MERGE (f1)-[:PRODUCES]->(pr1);
MATCH (f3:Factory {id:'F3'}), (pr1:Product {id:'PR1'}) MERGE (f3)-[:PRODUCES]->(pr1);

// Order SO1001
MERGE (o1:Order {id:'SO1001'}) SET o1.status = 'AtRisk';
MATCH (o1:Order {id:'SO1001'}), (pr1:Product {id:'PR1'}) MERGE (o1)-[:PRODUCES]->(pr1);
MATCH (o1:Order {id:'SO1001'}), (p1a:Part {id:'P1A'})   MERGE (o1)-[:REQUIRES]->(p1a);
MATCH (o1:Order {id:'SO1001'}), (p2b:Part {id:'P2B'})   MERGE (o1)-[:REQUIRES]->(p2b);

// Cross-system status for SO1001
MERGE (sr_crm:SystemRecord {system:'CRM', objectType:'Order', objectId:'SO1001'})
  SET sr_crm.status = 'Confirmed', sr_crm.updatedAt = datetime();
MERGE (sr_sap:SystemRecord {system:'SAP', objectType:'Order', objectId:'SO1001'})
  SET sr_sap.status = 'Procurement Open', sr_sap.updatedAt = datetime();
MERGE (sr_mes:SystemRecord {system:'MES', objectType:'Order', objectId:'SO1001'})
  SET sr_mes.status = 'Not Released', sr_mes.updatedAt = datetime();
MATCH (o1:Order {id:'SO1001'}), (sr:SystemRecord {objectId:'SO1001'}) MERGE (o1)-[:HAS_STATUS]->(sr);

// Risk event on S1
MERGE (r1:RiskEvent {id:'R1'}) SET r1.type = 'FactoryShutdown', r1.severity = 5, r1.date = date('2026-02-10');
MATCH (r1:RiskEvent {id:'R1'}), (s1:Supplier {id:'S1'}) MERGE (r1)-[:AFFECTS]->(s1);

// ── Extended SUPPLIES properties (S1→P1A, S2→P1A) ──

MATCH (s1:Supplier {id:'S1'}), (p1a:Part {id:'P1A'})
MERGE (s1)-[r:SUPPLIES]->(p1a)
SET r.priority = 1, r.leadTimeDays = 14,
    r.moq = 100, r.capacity = 5000, r.lastPrice = 12.50,
    r.qualificationLevel = 'Full';

MATCH (s2:Supplier {id:'S2'}), (p1a:Part {id:'P1A'})
MERGE (s2)-[r:SUPPLIES]->(p1a)
SET r.priority = 2, r.leadTimeDays = 10,
    r.moq = 200, r.capacity = 3000, r.lastPrice = 14.80,
    r.qualificationLevel = 'Conditional';

MATCH (s5:Supplier {id:'S5'}), (p1b:Part {id:'P1B'})
MERGE (s5)-[r:SUPPLIES]->(p1b)
SET r.priority = 1, r.leadTimeDays = 7,
    r.moq = 50, r.capacity = 8000, r.lastPrice = 3.20,
    r.qualificationLevel = 'Full';

MATCH (s3:Supplier {id:'S3'}), (p2a:Part {id:'P2A'})
MERGE (s3)-[r:SUPPLIES]->(p2a)
SET r.priority = 1, r.leadTimeDays = 12,
    r.moq = 150, r.capacity = 4000, r.lastPrice = 8.90,
    r.qualificationLevel = 'Full';

MATCH (s4:Supplier {id:'S4'}), (p2b:Part {id:'P2B'})
MERGE (s4)-[r:SUPPLIES]->(p2b)
SET r.priority = 1, r.leadTimeDays = 5,
    r.moq = 300, r.capacity = 10000, r.lastPrice = 1.80,
    r.qualificationLevel = 'Full';

// Back-fill extended props on all other SUPPLIES relationships that lack them
MATCH ()-[r:SUPPLIES]->() WHERE r.moq IS NULL
SET r.moq              = toInteger(50 + rand() * 450),
    r.capacity         = toInteger(1000 + rand() * 9000),
    r.lastPrice        = toFloat(round((rand() * 50 + 1) * 100) / 100),
    r.qualificationLevel = CASE toInteger(rand() * 3)
                             WHEN 0 THEN 'Full'
                             WHEN 1 THEN 'Conditional'
                             ELSE 'Pending' END;

// ── TransportLane nodes ──

MERGE (tl:TransportLane {id:'LANE-S1-F1-Ocean'})
  SET tl.fromNode='S1', tl.toNode='F1', tl.mode='Ocean', tl.timeDays=21, tl.cost=0.50, tl.reliability=0.92;
MERGE (tl:TransportLane {id:'LANE-S1-F1-Air'})
  SET tl.fromNode='S1', tl.toNode='F1', tl.mode='Air',   tl.timeDays=3,  tl.cost=4.80, tl.reliability=0.98;
MERGE (tl:TransportLane {id:'LANE-S2-F1-Ocean'})
  SET tl.fromNode='S2', tl.toNode='F1', tl.mode='Ocean', tl.timeDays=14, tl.cost=0.60, tl.reliability=0.90;
MERGE (tl:TransportLane {id:'LANE-S2-F1-Air'})
  SET tl.fromNode='S2', tl.toNode='F1', tl.mode='Air',   tl.timeDays=2,  tl.cost=5.20, tl.reliability=0.97;
MERGE (tl:TransportLane {id:'LANE-S1-F3-Ocean'})
  SET tl.fromNode='S1', tl.toNode='F3', tl.mode='Ocean', tl.timeDays=18, tl.cost=0.55, tl.reliability=0.88;
MERGE (tl:TransportLane {id:'LANE-S1-F3-Air'})
  SET tl.fromNode='S1', tl.toNode='F3', tl.mode='Air',   tl.timeDays=4,  tl.cost=5.00, tl.reliability=0.96;
MERGE (tl:TransportLane {id:'LANE-S2-F3-Ocean'})
  SET tl.fromNode='S2', tl.toNode='F3', tl.mode='Ocean', tl.timeDays=12, tl.cost=0.65, tl.reliability=0.91;
MERGE (tl:TransportLane {id:'LANE-S2-F3-Air'})
  SET tl.fromNode='S2', tl.toNode='F3', tl.mode='Air',   tl.timeDays=3,  tl.cost=5.50, tl.reliability=0.95;

// Link lanes → suppliers / factories
MATCH (s:Supplier {id:'S1'}), (tl:TransportLane) WHERE tl.fromNode = 'S1' MERGE (s)-[:HAS_LANE]->(tl);
MATCH (s:Supplier {id:'S2'}), (tl:TransportLane) WHERE tl.fromNode = 'S2' MERGE (s)-[:HAS_LANE]->(tl);
MATCH (f:Factory  {id:'F1'}), (tl:TransportLane) WHERE tl.toNode   = 'F1' MERGE (tl)-[:LANE_TO]->(f);
MATCH (f:Factory  {id:'F3'}), (tl:TransportLane) WHERE tl.toNode   = 'F3' MERGE (tl)-[:LANE_TO]->(f);

// ── InventoryLot: add safetyStock everywhere + ensure P1A lot ──

MERGE (inv:InventoryLot {id:'LOT-P1A-F1'})
  SET inv.location = 'F1-WH', inv.onHand = 200, inv.reserved = 150, inv.safetyStock = 50;
MATCH (inv:InventoryLot {id:'LOT-P1A-F1'}), (p:Part {id:'P1A'}) MERGE (inv)-[:STORES]->(p);

// Back-fill safetyStock on all lots that lack it
MATCH (inv:InventoryLot) WHERE inv.safetyStock IS NULL
SET inv.safetyStock = toInteger(20 + rand() * 80);

// ── QualityHold (optional demo record) ──

MERGE (qh:QualityHold {id:'QH-S2-P1A'})
  SET qh.supplierId = 'S2', qh.partId = 'P1A', qh.holdDays = 5,
      qh.reason = 'New supplier qualification pending';
