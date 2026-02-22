// Clean demo nodes (safe-ish for demo DB)
MATCH (n)
WHERE any(l IN labels(n) WHERE l IN ['Factory','Supplier','Part','Product','Order','SystemRecord','RiskEvent','Shipment','InventoryLot'])
DETACH DELETE n;

// Factories
CREATE (f1:Factory {id:'F1', name:'Shanghai Plant'})
CREATE (f2:Factory {id:'F2', name:'Suzhou Plant'})
CREATE (f3:Factory {id:'F3', name:'Chongqing Backup Plant'})
CREATE (f1)-[:CAN_BACKUP_WITH]->(f3);

// Suppliers
CREATE (s1:Supplier {id:'S1', name:'TaiwanChipCo'})
CREATE (s2:Supplier {id:'S2', name:'KoreaChipBackup'})
CREATE (s3:Supplier {id:'S3', name:'JapanSensor'})
CREATE (s4:Supplier {id:'S4', name:'SuzhouPCB'})
CREATE (s5:Supplier {id:'S5', name:'ShenzhenPower'})
CREATE (s2)-[:ALTERNATIVE_TO]->(s1);

// Parts & Product
CREATE (pr1:Product {id:'PR1', name:'Smart Control System'})
CREATE (p1:Part {id:'P1', name:'MainBoard', partType:'ASSEMBLY'})
CREATE (p2:Part {id:'P2', name:'Sensor Module', partType:'ASSEMBLY'})
CREATE (p3:Part {id:'P3', name:'Housing', partType:'COMPONENT'})

CREATE (p1a:Part {id:'P1A', name:'MCU Chip', partType:'COMPONENT'})
CREATE (p1b:Part {id:'P1B', name:'Power Module', partType:'COMPONENT'})
CREATE (p2a:Part {id:'P2A', name:'Sensor Chip', partType:'COMPONENT'})
CREATE (p2b:Part {id:'P2B', name:'PCB Board', partType:'COMPONENT'})

// Multi-level BOM
CREATE (pr1)-[:HAS_COMPONENT]->(p1)
CREATE (pr1)-[:HAS_COMPONENT]->(p2)
CREATE (pr1)-[:HAS_COMPONENT]->(p3)

CREATE (p1)-[:HAS_COMPONENT]->(p1a)
CREATE (p1)-[:HAS_COMPONENT]->(p1b)

CREATE (p2)-[:HAS_COMPONENT]->(p2a)
CREATE (p2)-[:HAS_COMPONENT]->(p2b)

// Supply relationships
CREATE (s1)-[:SUPPLIES {priority:1, leadTimeDays:14}]->(p1a)
CREATE (s2)-[:SUPPLIES {priority:2, leadTimeDays:10}]->(p1a)
CREATE (s5)-[:SUPPLIES {priority:1, leadTimeDays:7}]->(p1b)
CREATE (s3)-[:SUPPLIES {priority:1, leadTimeDays:12}]->(p2a)
CREATE (s4)-[:SUPPLIES {priority:1, leadTimeDays:5}]->(p2b)

// Factories produce
CREATE (f1)-[:PRODUCES]->(pr1)
CREATE (f2)-[:PRODUCES]->(p1)
CREATE (f2)-[:PRODUCES]->(p2)
CREATE (f3)-[:PRODUCES]->(pr1)

// Orders + cross-system status mirror
CREATE (o1:Order {id:'SO1001', status:'AtRisk'})
CREATE (o2:Order {id:'SO1002', status:'Confirmed'})

CREATE (o1)-[:PRODUCES]->(pr1)
CREATE (o1)-[:REQUIRES]->(p1a)
CREATE (o1)-[:REQUIRES]->(p2b)

CREATE (sr_crm:SystemRecord {system:'CRM', objectType:'Order', objectId:'SO1001', status:'Confirmed', updatedAt:datetime()})
CREATE (sr_sap:SystemRecord {system:'SAP', objectType:'Order', objectId:'SO1001', status:'Procurement Open', updatedAt:datetime()})
CREATE (sr_mes:SystemRecord {system:'MES', objectType:'Order', objectId:'SO1001', status:'Not Released', updatedAt:datetime()})

CREATE (o1)-[:HAS_STATUS]->(sr_crm)
CREATE (o1)-[:HAS_STATUS]->(sr_sap)
CREATE (o1)-[:HAS_STATUS]->(sr_mes)

// Risk event affecting supplier S1 (MCU)
CREATE (r1:RiskEvent {id:'R1', type:'FactoryShutdown', severity:5, date:date('2026-02-10')})
CREATE (r1)-[:AFFECTS]->(s1);

// Shipment & inventory objects (lightweight)
CREATE (sh1:Shipment {id:'SHIP-3001', mode:'Ocean', status:'InTransit', eta:date('2026-02-18')})
CREATE (sh1)-[:DELIVERS]->(p1a)
CREATE (inv1:InventoryLot {id:'LOT-4001', location:'F1-WH', onHand:200, reserved:150})
CREATE (inv1)-[:STORES]->(p1a);
