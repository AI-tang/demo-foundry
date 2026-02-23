export const typeDefs = /* GraphQL */ `
  type Factory {
    id: String!
    name: String!
    produces: [Product!]! @relationship(type: "PRODUCES", direction: OUT)
    canBackupWith: [Factory!]! @relationship(type: "CAN_BACKUP_WITH", direction: OUT)
  }

  type Supplier {
    id: String!
    name: String!
    supplies: [Part!]! @relationship(type: "SUPPLIES", direction: OUT, properties: "SuppliesProperties")
    alternativeTo: [Supplier!]! @relationship(type: "ALTERNATIVE_TO", direction: OUT)
    affectedBy: [RiskEvent!]! @relationship(type: "AFFECTS", direction: IN)
    lanes: [TransportLane!]! @relationship(type: "HAS_LANE", direction: OUT)
  }

  type SuppliesProperties @relationshipProperties {
    priority: Int
    leadTimeDays: Int
    moq: Int
    capacity: Int
    lastPrice: Float
    qualificationLevel: String
  }

  type Part {
    id: String!
    name: String!
    partType: String!
    components: [Part!]! @relationship(type: "HAS_COMPONENT", direction: OUT)
    parentOf: [Part!]! @relationship(type: "HAS_COMPONENT", direction: IN)
    suppliedBy: [Supplier!]! @relationship(type: "SUPPLIES", direction: IN, properties: "SuppliesProperties")
    inventoryLots: [InventoryLot!]! @relationship(type: "STORES", direction: IN)
    deliveredBy: [Shipment!]! @relationship(type: "DELIVERS", direction: IN)
  }

  type Product {
    id: String!
    name: String!
    components: [Part!]! @relationship(type: "HAS_COMPONENT", direction: OUT)
    producedBy: [Factory!]! @relationship(type: "PRODUCES", direction: IN)
    orders: [Order!]! @relationship(type: "PRODUCES", direction: IN)
  }

  type Order {
    id: String!
    status: String!
    produces: [Product!]! @relationship(type: "PRODUCES", direction: OUT)
    requires: [Part!]! @relationship(type: "REQUIRES", direction: OUT)
    statuses: [SystemRecord!]! @relationship(type: "HAS_STATUS", direction: OUT)
  }

  type SystemRecord {
    system: String!
    objectType: String!
    objectId: String!
    status: String!
    updatedAt: DateTime
  }

  type RiskEvent {
    id: String!
    type: String!
    severity: Int!
    date: Date
    affects: [Supplier!]! @relationship(type: "AFFECTS", direction: OUT)
  }

  type Shipment {
    id: String!
    mode: String!
    status: String!
    eta: Date
    delivers: [Part!]! @relationship(type: "DELIVERS", direction: OUT)
  }

  type InventoryLot {
    id: String!
    location: String!
    onHand: Int!
    reserved: Int!
    safetyStock: Int
    stores: [Part!]! @relationship(type: "STORES", direction: OUT)
  }

  type TransportLane {
    id: String!
    fromNode: String!
    toNode: String!
    mode: String!
    timeDays: Int!
    cost: Float!
    reliability: Float!
    laneTo: [Factory!]! @relationship(type: "LANE_TO", direction: OUT)
  }

  type QualityHold {
    id: String!
    supplierId: String!
    partId: String!
    holdDays: Int!
    reason: String
  }

  type DefectEvent {
    id: String!
    description: String!
    severity: Int!
    date: Date
    affectsPart: [Part!]! @relationship(type: "HAS_DEFECT", direction: IN)
  }

  type ECO {
    id: String!
    description: String!
    status: String!
    date: Date
    affectedParts: [Part!]! @relationship(type: "ECO_AFFECTS", direction: OUT)
    replacementPart: [Part!]! @relationship(type: "ECO_REPLACES_WITH", direction: OUT)
  }

  type Query {
    ordersAtRisk: [Order!]! @cypher(
      statement: """
      MATCH (o:Order {status:'AtRisk'})-[:PRODUCES]->(pr:Product)
      OPTIONAL MATCH (o)-[:REQUIRES]->(p:Part)<-[:SUPPLIES]-(s:Supplier)<-[:AFFECTS]-(r:RiskEvent)
      RETURN o { .id, .status } ORDER BY o.id LIMIT 50
      """
      columnName: "o"
    )

    missingParts: [Part!]! @cypher(
      statement: """
      MATCH (o:Order)-[:REQUIRES]->(p:Part)
      OPTIONAL MATCH (inv:InventoryLot)-[:STORES]->(p)
      WITH p, sum(coalesce(inv.onHand,0) - coalesce(inv.reserved,0)) AS avail
      WHERE avail <= 0
      RETURN DISTINCT p { .id, .name, .partType }
      """
      columnName: "p"
    )

    lineStopForecast: [Order!]! @cypher(
      statement: """
      MATCH (o:Order)-[:REQUIRES]->(p:Part)
      OPTIONAL MATCH (inv:InventoryLot)-[:STORES]->(p)
      WITH o, p, sum(coalesce(inv.onHand,0) - coalesce(inv.reserved,0)) AS avail
      WHERE avail <= 0
      OPTIONAL MATCH (p)<-[:SUPPLIES]-(s:Supplier)<-[:AFFECTS]-(r:RiskEvent)
      WITH o, collect(DISTINCT p.id) AS shortParts, collect(DISTINCT r.id) AS risks
      WHERE size(shortParts) > 0
      RETURN o { .id, .status } ORDER BY size(risks) DESC, o.id LIMIT 20
      """
      columnName: "o"
    )

    traceQuality(defectId: String!): [DefectEvent!]! @cypher(
      statement: """
      MATCH (d:DefectEvent {id: $defectId})
      RETURN d { .id, .description, .severity }
      """
      columnName: "d"
    )

    ecoImpact(ecoId: String!): [ECO!]! @cypher(
      statement: """
      MATCH (e:ECO {id: $ecoId})
      RETURN e { .id, .description, .status }
      """
      columnName: "e"
    )

    reconcile: [Order!]! @cypher(
      statement: """
      MATCH (o:Order)-[:HAS_STATUS]->(s:SystemRecord)
      WITH o, collect(DISTINCT s.status) AS statuses
      WHERE size(statuses) > 1
      RETURN o { .id, .status } ORDER BY o.id
      """
      columnName: "o"
    )
  }
`;
