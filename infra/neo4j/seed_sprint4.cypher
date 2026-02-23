// Sprint 4 — Sourcing data extensions
// Runs AFTER seed_sprint2.cypher (additive, uses MERGE)

// ── New Suppliers ──
MERGE (s6:Supplier  {id:'S6'})  SET s6.name  = 'ShanghaiElec';
MERGE (s7:Supplier  {id:'S7'})  SET s7.name  = 'GuangzhouSemi';
MERGE (s8:Supplier  {id:'S8'})  SET s8.name  = 'BeijingOptics';
MERGE (s9:Supplier  {id:'S9'})  SET s9.name  = 'WuhanPower';
MERGE (s10:Supplier {id:'S10'}) SET s10.name = 'ChengduMicro';
MERGE (s11:Supplier {id:'S11'}) SET s11.name = 'TaipeiLogic';
MERGE (s12:Supplier {id:'S12'}) SET s12.name = 'SeoulMemory';
MERGE (s13:Supplier {id:'S13'}) SET s13.name = 'TokyoSensor';
MERGE (s14:Supplier {id:'S14'}) SET s14.name = 'OsakaPCB';
MERGE (s15:Supplier {id:'S15'}) SET s15.name = 'HanoiConnect';

// ── ALTERNATIVE_TO relationships (second-source pairs) ──
MATCH (s1:Supplier {id:'S1'}),  (s2:Supplier {id:'S2'})  MERGE (s2)-[:ALTERNATIVE_TO]->(s1);
MATCH (s1:Supplier {id:'S1'}),  (s10:Supplier {id:'S10'}) MERGE (s10)-[:ALTERNATIVE_TO]->(s1);
MATCH (s3:Supplier {id:'S3'}),  (s13:Supplier {id:'S13'}) MERGE (s13)-[:ALTERNATIVE_TO]->(s3);
MATCH (s3:Supplier {id:'S3'}),  (s8:Supplier {id:'S8'})  MERGE (s8)-[:ALTERNATIVE_TO]->(s3);
MATCH (s4:Supplier {id:'S4'}),  (s14:Supplier {id:'S14'}) MERGE (s14)-[:ALTERNATIVE_TO]->(s4);
MATCH (s5:Supplier {id:'S5'}),  (s9:Supplier {id:'S9'})  MERGE (s9)-[:ALTERNATIVE_TO]->(s5);
MATCH (s6:Supplier {id:'S6'}),  (s14:Supplier {id:'S14'}) MERGE (s14)-[:ALTERNATIVE_TO]->(s6);
MATCH (s7:Supplier {id:'S7'}),  (s11:Supplier {id:'S11'}) MERGE (s11)-[:ALTERNATIVE_TO]->(s7);
MATCH (s11:Supplier {id:'S11'}),(s12:Supplier {id:'S12'}) MERGE (s12)-[:ALTERNATIVE_TO]->(s11);

// ── Key bottleneck Part nodes ──
MERGE (mcu1:Part {id:'MCU-001'}) SET mcu1.name = 'MCU Chip Model 1', mcu1.partType = 'COMPONENT';
MERGE (mcu5:Part {id:'MCU-005'}) SET mcu5.name = 'MCU Chip Model 5', mcu5.partType = 'COMPONENT';
MERGE (ic1:Part  {id:'IC-001'})  SET ic1.name  = 'IC Chip 1',        ic1.partType  = 'COMPONENT';
MERGE (ic5:Part  {id:'IC-005'})  SET ic5.name  = 'IC Chip 5',        ic5.partType  = 'COMPONENT';
MERGE (cap1:Part {id:'CAP-001'}) SET cap1.name = 'Capacitor 1',      cap1.partType = 'COMPONENT';
MERGE (sns1:Part {id:'SNS-001'}) SET sns1.name = 'Sensor Module 1',  sns1.partType = 'COMPONENT';
MERGE (pcb1:Part {id:'PCB-001'}) SET pcb1.name = 'PCB Board 1',      pcb1.partType = 'COMPONENT';
MERGE (pwr1:Part {id:'PWR-001'}) SET pwr1.name = 'Power Module 1',   pwr1.partType = 'COMPONENT';
MERGE (mem1:Part {id:'MEM-001'}) SET mem1.name = 'Memory Module 1',  mem1.partType = 'COMPONENT';
MERGE (dsp1:Part {id:'DSP-001'}) SET dsp1.name = 'Display Module 1', dsp1.partType = 'COMPONENT';
MERGE (con1:Part {id:'CON-001'}) SET con1.name = 'Connector 1',      con1.partType = 'COMPONENT';
MERGE (res1:Part {id:'RES-001'}) SET res1.name = 'Resistor 1',       res1.partType = 'COMPONENT';

// ── SUPPLIES relationships with extended properties ──

// MCU-001: single-source S1 only (bottleneck!)
MATCH (s:Supplier {id:'S1'}), (p:Part {id:'MCU-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=12, r.moq=500, r.capacityPerWeek=2100, r.price=10.50, r.qualificationLevel='Full';

// MCU-005: S1 + S2 + S10
MATCH (s:Supplier {id:'S1'}), (p:Part {id:'MCU-005'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=14, r.moq=500, r.capacityPerWeek=2500, r.price=12.80, r.qualificationLevel='Full';

MATCH (s:Supplier {id:'S2'}), (p:Part {id:'MCU-005'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=2, r.leadTimeDays=11, r.moq=200, r.capacityPerWeek=3000, r.price=11.20, r.qualificationLevel='Conditional';

MATCH (s:Supplier {id:'S10'}), (p:Part {id:'MCU-005'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=3, r.leadTimeDays=17, r.moq=600, r.capacityPerWeek=1500, r.price=14.50, r.qualificationLevel='Pending';

// IC-001: S1 + S2 + S11
MATCH (s:Supplier {id:'S1'}), (p:Part {id:'IC-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=2, r.leadTimeDays=14, r.moq=300, r.capacityPerWeek=1580, r.price=8.50, r.qualificationLevel='Full';

MATCH (s:Supplier {id:'S2'}), (p:Part {id:'IC-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=2, r.leadTimeDays=11, r.moq=250, r.capacityPerWeek=2500, r.price=7.80, r.qualificationLevel='Conditional';

MATCH (s:Supplier {id:'S11'}), (p:Part {id:'IC-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=12, r.moq=250, r.capacityPerWeek=3000, r.price=8.20, r.qualificationLevel='Full';

// CAP-001: single-source S6 only (bottleneck!)
MATCH (s:Supplier {id:'S6'}), (p:Part {id:'CAP-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=5, r.moq=1000, r.capacityPerWeek=20000, r.price=0.05, r.qualificationLevel='Full';

// SNS-001: S3 + S13
MATCH (s:Supplier {id:'S3'}), (p:Part {id:'SNS-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=10, r.moq=100, r.capacityPerWeek=4000, r.price=6.10, r.qualificationLevel='Full';

MATCH (s:Supplier {id:'S13'}), (p:Part {id:'SNS-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=2, r.leadTimeDays=11, r.moq=120, r.capacityPerWeek=3500, r.price=6.60, r.qualificationLevel='Full';

// PCB-001: S4 + S14
MATCH (s:Supplier {id:'S4'}), (p:Part {id:'PCB-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=5, r.moq=300, r.capacityPerWeek=10000, r.price=1.50, r.qualificationLevel='Full';

MATCH (s:Supplier {id:'S14'}), (p:Part {id:'PCB-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=2, r.leadTimeDays=7, r.moq=250, r.capacityPerWeek=8000, r.price=1.80, r.qualificationLevel='Full';

// PWR-001: S5 only (+ S9 backup for PWR-005+)
MATCH (s:Supplier {id:'S5'}), (p:Part {id:'PWR-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=7, r.moq=50, r.capacityPerWeek=8000, r.price=3.10, r.qualificationLevel='Full';

// MEM-001: S7 + S12
MATCH (s:Supplier {id:'S7'}), (p:Part {id:'MEM-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=15, r.moq=200, r.capacityPerWeek=3000, r.price=18.90, r.qualificationLevel='Full';

MATCH (s:Supplier {id:'S12'}), (p:Part {id:'MEM-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=13, r.moq=100, r.capacityPerWeek=4000, r.price=17.50, r.qualificationLevel='Full';

// DSP-001: S8 only (single-source!)
MATCH (s:Supplier {id:'S8'}), (p:Part {id:'DSP-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=14, r.moq=100, r.capacityPerWeek=2000, r.price=22.50, r.qualificationLevel='Full';

// CON-001: S6 + S14
MATCH (s:Supplier {id:'S6'}), (p:Part {id:'CON-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=6, r.moq=200, r.capacityPerWeek=6000, r.price=0.82, r.qualificationLevel='Full';

// RES-001: S10
MATCH (s:Supplier {id:'S10'}), (p:Part {id:'RES-001'})
MERGE (s)-[r:SUPPLIES]->(p)
SET r.priority=1, r.leadTimeDays=4, r.moq=2000, r.capacityPerWeek=50000, r.price=0.02, r.qualificationLevel='Full';

// ── Factories (ensure F2 exists) ──
MERGE (f2:Factory {id:'F2'}) SET f2.name = 'Suzhou Plant';

// ── Risk events on new suppliers ──
MERGE (r2:RiskEvent {id:'R2'}) SET r2.type = 'QualityIncident', r2.severity = 3, r2.date = date('2026-02-15');
MATCH (r2:RiskEvent {id:'R2'}), (s8:Supplier {id:'S8'}) MERGE (r2)-[:AFFECTS]->(s8);

MERGE (r3:RiskEvent {id:'R3'}) SET r3.type = 'LogisticsDelay', r3.severity = 2, r3.date = date('2026-02-12');
MATCH (r3:RiskEvent {id:'R3'}), (s15:Supplier {id:'S15'}) MERGE (r3)-[:AFFECTS]->(s15);

// ── Demand-related orders in Neo4j (key ones for visibility) ──
MERGE (o:Order {id:'SO1101'}) SET o.status = 'InProgress';
MATCH (o:Order {id:'SO1101'}), (p:Part {id:'MCU-001'}) MERGE (o)-[:REQUIRES]->(p);
MERGE (o:Order {id:'SO1102'}) SET o.status = 'InProgress';
MATCH (o:Order {id:'SO1102'}), (p:Part {id:'MCU-001'}) MERGE (o)-[:REQUIRES]->(p);
MERGE (o:Order {id:'SO1103'}) SET o.status = 'AtRisk';
MATCH (o:Order {id:'SO1103'}), (p:Part {id:'MCU-001'}) MERGE (o)-[:REQUIRES]->(p);

MERGE (o:Order {id:'SO1201'}) SET o.status = 'InProgress';
MATCH (o:Order {id:'SO1201'}), (p:Part {id:'IC-001'}) MERGE (o)-[:REQUIRES]->(p);
MERGE (o:Order {id:'SO1202'}) SET o.status = 'AtRisk';
MATCH (o:Order {id:'SO1202'}), (p:Part {id:'IC-001'}) MERGE (o)-[:REQUIRES]->(p);

MERGE (o:Order {id:'SO1301'}) SET o.status = 'InProgress';
MATCH (o:Order {id:'SO1301'}), (p:Part {id:'CAP-001'}) MERGE (o)-[:REQUIRES]->(p);

// ── Transport lanes for new suppliers (Neo4j nodes) ──
MERGE (tl:TransportLane {id:'LANE-S6-F1-Truck'})
  SET tl.fromNode='S6', tl.toNode='F1', tl.mode='Truck', tl.timeDays=2, tl.cost=0.20, tl.reliability=0.95;
MERGE (tl:TransportLane {id:'LANE-S7-F1-Truck'})
  SET tl.fromNode='S7', tl.toNode='F1', tl.mode='Truck', tl.timeDays=3, tl.cost=0.35, tl.reliability=0.93;
MERGE (tl:TransportLane {id:'LANE-S8-F1-Air'})
  SET tl.fromNode='S8', tl.toNode='F1', tl.mode='Air', tl.timeDays=2, tl.cost=4.00, tl.reliability=0.97;
MERGE (tl:TransportLane {id:'LANE-S11-F1-Ocean'})
  SET tl.fromNode='S11', tl.toNode='F1', tl.mode='Ocean', tl.timeDays=10, tl.cost=0.55, tl.reliability=0.92;
MERGE (tl:TransportLane {id:'LANE-S12-F1-Ocean'})
  SET tl.fromNode='S12', tl.toNode='F1', tl.mode='Ocean', tl.timeDays=12, tl.cost=0.58, tl.reliability=0.91;
MERGE (tl:TransportLane {id:'LANE-S13-F1-Ocean'})
  SET tl.fromNode='S13', tl.toNode='F1', tl.mode='Ocean', tl.timeDays=16, tl.cost=0.48, tl.reliability=0.92;

// Link new lanes
MATCH (s:Supplier {id:'S6'}),  (tl:TransportLane) WHERE tl.fromNode = 'S6'  MERGE (s)-[:HAS_LANE]->(tl);
MATCH (s:Supplier {id:'S7'}),  (tl:TransportLane) WHERE tl.fromNode = 'S7'  MERGE (s)-[:HAS_LANE]->(tl);
MATCH (s:Supplier {id:'S8'}),  (tl:TransportLane) WHERE tl.fromNode = 'S8'  MERGE (s)-[:HAS_LANE]->(tl);
MATCH (s:Supplier {id:'S11'}), (tl:TransportLane) WHERE tl.fromNode = 'S11' MERGE (s)-[:HAS_LANE]->(tl);
MATCH (s:Supplier {id:'S12'}), (tl:TransportLane) WHERE tl.fromNode = 'S12' MERGE (s)-[:HAS_LANE]->(tl);
MATCH (s:Supplier {id:'S13'}), (tl:TransportLane) WHERE tl.fromNode = 'S13' MERGE (s)-[:HAS_LANE]->(tl);
MATCH (f:Factory {id:'F1'}), (tl:TransportLane) WHERE tl.toNode = 'F1' AND NOT EXISTS { (tl)-[:LANE_TO]->(:Factory) } MERGE (tl)-[:LANE_TO]->(f);
