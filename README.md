# Demo Foundry — Supply Chain Digital Twin

A **Palantir Foundry-style** demo platform for supply chain management, featuring multi-source data integration, ontology graph, what-if simulation, multi-agent workflow, and intelligent sourcing — all running locally via Docker Compose.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Control Tower UI (:3000)                      │
│                     React / Vite / Apollo Client                     │
└──────────────────────┬───────────────────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────────────────┐
│                      GraphQL API (:4000)                             │
│          Apollo Server + @neo4j/graphql + Chat (OpenAI)              │
└───────┬──────────────┬──────────────────┬────────────────────────────┘
        │              │                  │
┌───────▼──────┐ ┌─────▼──────┐   ┌──────▼───────┐
│ Twin-Sim     │ │ Agent-API  │   │   Neo4j      │
│ (:7100)      │ │ (:7200)    │   │ (:7474/7687) │
│ What-If Sim  │ │ Workflow + │   │ Ontology     │
│ FastAPI      │ │ Sourcing   │   │ Graph        │
└──────────────┘ │ FastAPI    │   └──────────────┘
                 └──────┬─────┘
                        │
        ┌───────────────┼───────────────┐
┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
│ Postgres CRM │ │ Postgres ERP│ │ Postgres MES│
│ (:54321)     │ │ (:54322)    │ │ (:54323)    │
└──────────────┘ └─────────────┘ └─────────────┘
        │              │               │
┌───────▼──────────────▼───────────────▼───────┐
│              Trino (:8080)                    │
│   Federated query: CRM + ERP + MES + Iceberg │
└──────────────────────┬───────────────────────┘
                       │
          ┌────────────▼────────────┐
          │  MinIO (:9000) + Nessie │
          │  Iceberg Data Lake      │
          └─────────────────────────┘
```

**13 services** running locally — all orchestrated by Docker Compose.

## Quick Start

### Prerequisites (macOS / Linux)
- Docker Desktop (running)
- `make` (Xcode CLT on macOS)
- (Optional) `OPENAI_API_KEY` env var for chat NL features

### Boot & Verify

```bash
make up          # Start all 13 containers
make seed        # Seed databases (Postgres + Neo4j + Iceberg)
make smoke       # Run full smoke test suite
```

### Other Commands

```bash
make down        # Stop all containers
make ps          # Container status
make logs        # Tail all logs
make reset       # Full reset: down -v → up → seed → smoke
make demo-sprint3  # Run Sprint 3 end-to-end demo script
```

## Useful URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Control Tower UI | http://localhost:3000 | — |
| GraphQL Playground | http://localhost:4000/graphql | — |
| Neo4j Browser | http://localhost:7474 | `neo4j` / `demo12345` |
| Trino UI | http://localhost:8080 | — |
| MinIO Console | http://localhost:9001 | `minio` / `minio12345` |
| Agent-API Docs | http://localhost:7200/docs | — |
| Twin-Sim Docs | http://localhost:7100/docs | — |
| Debezium Connect | http://localhost:8083 | — |

## Sprint Roadmap

### Sprint 0 — Infrastructure Foundation

Lay down the data backbone: 3 mock source systems + CDC pipeline + query federation.

| Component | Details |
|-----------|---------|
| **CRM** (Postgres) | `customers`, `crm_orders` — 100+ orders |
| **ERP** (Postgres) | `suppliers`, `parts`, `supplier_parts`, `purchase_orders`, `shipments`, `inventory_lots` |
| **MES** (Postgres) | `factories`, `machines`, `production_orders`, `work_orders` |
| **Neo4j Ontology** | Factory, Supplier, Part, Product, Order, RiskEvent — multi-factory, multi-supplier, multi-level BOM |
| **Kafka + Debezium** | CDC from Postgres → Kafka topics |
| **Trino** | Federated SQL across CRM / ERP / MES catalogs |
| **MinIO + Nessie** | S3-compatible storage + REST catalog for Iceberg |

**Data model**: 3 factories (F1/F2/F3 with `CAN_BACKUP_WITH` links), 5 suppliers (S1-S5), 4 parts, 100+ cross-system orders with synchronized status tracking.

---

### Sprint 1 — GraphQL API, Iceberg & Control Tower UI

Add a unified API layer, data lake, and visual dashboard.

**GraphQL API** (`services/graphql-api`, port 4000):
- Auto-generated CRUD via `@neo4j/graphql` for all ontology entities
- `@cypher` directive queries: `ordersAtRisk`, `missingParts`, `lineStopForecast`, `traceQuality`, `ecoImpact`, `reconcile`
- Bilingual chat endpoint (`POST /chat`) with OpenAI-powered NL → GraphQL/Cypher translation (Chinese & English)

**Iceberg Data Lake**:
- Nessie-backed Iceberg tables on MinIO (Parquet format)
- `iceberg.warehouse.orders` and `iceberg.warehouse.supply_chain`
- Queryable via Trino alongside Postgres catalogs

**Control Tower UI** (`services/control-tower-ui`, port 3000):
- React + Vite + Apollo Client
- Dashboard, Orders Table, BOM Tree, Supply Chain Map, Risk Alerts, Chat Panel

**Scenario Pack** — 5 pre-built supply chain scenarios:
1. **Missing Parts** — BOM gap analysis
2. **Supplier Risk** — disruption propagation
3. **Quality Trace** — defect root-cause tracing
4. **ECO Change** — engineering change impact
5. **Cross-System Conflict** — CRM/ERP/MES status mismatch

**Data scale**: parametric generator (`scripts/generate_demo_data.py`) → 3 factories, 10 suppliers, 200+ parts, 100+ orders.

---

### Sprint 2 — What-If Digital Twin Simulation

Rule-based scenario simulation with explainable A/B/C comparison and blast-radius analysis.

**Twin-Sim Service** (`services/twin-sim`, port 7100, FastAPI):

| Endpoint | What-If Question |
|----------|-----------------|
| `POST /simulate/switch-supplier` | "What if we switch P1A from S1 to S2?" |
| `POST /simulate/change-lane` | "What if we ship via Air instead of Ocean?" |
| `POST /simulate/transfer-factory` | "What if we move production to backup factory F2?" |

Each returns **3 scenarios** (A / B / C) with:
- `eta_delta_days` — delivery impact
- `cost_delta_pct` — cost impact
- `line_stop_risk` — probability of production stoppage (0–1)
- `quality_risk` — quality risk factor (0–1)
- `assumptions` — explainable reasoning
- `recommended` — best scenario pick

**Blast Radius** (`blastRadius` GraphQL query):
- Given an order or supplier disruption, trace impact through the graph
- Returns: `impactedOrders`, `impactedParts`, `impactedFactories`, propagation paths

**Neo4j extensions**: `TransportLane` nodes (mode, timeDays, cost, reliability), extended `SUPPLIES` properties (moq, capacity, lastPrice, qualificationLevel), `QualityHold` tracking.

**Chat integration**: NL intent detection for what-if questions → automatic twin-sim invocation → scenario summary.

---

### Sprint 3 — Multi-Agent Workflow + ERP Writeback + Audit

Close the loop: **explain → recommend → execute → audit**. Natural language question in, PO/shipment writeback out, full audit trail recorded.

**Agent-API Service** (`services/agent-api`, port 7200, FastAPI):

| Role | Endpoint | Function |
|------|----------|----------|
| **Integrator** | `POST /agent/plan` | Intent classification → step decomposition |
| **Analyst** | `POST /agent/analyze` | Gather context from ERP/Neo4j, compose root-cause explanation |
| **Simulator** | `POST /agent/simulate` | Invoke twin-sim, evaluate scenarios, provide rationale |
| **Executor** | `POST /agent/execute` | Qualification check → ERP writeback → audit trail |

**Supported actions**:

| Action | What It Does |
|--------|-------------|
| `CREATE_PO` | Validate supplier qualification + capacity → INSERT `purchase_orders` |
| `EXPEDITE_SHIPMENT` | Find shipment by PO → UPDATE mode/ETA to Air |

**Audit trail** (Postgres ERP):
- `audit_events`: event_id, timestamp, actor, action, input/output (JSONB), status
- `action_requests`: request_id, type, payload, approval_status

**Chat action detection**: "帮我向S2下500个P1A的采购单" → detects `CREATE_PO` intent → agent-api execute → returns PO ID + audit event.

**Demo script**: `make demo-sprint3` runs a full 10-step end-to-end workflow.

---

### Sprint 4 — Sourcing Scenarios (RFQ + Single-Source + MOQ)

Intelligent procurement with explainable scoring, governance checks, and demand consolidation.

**Data expansion**: 5 → **15 suppliers**, 4 → **438 parts**, **140 demand records**, **43 transport lanes**, **20 RFQ quotes**.

**Three sourcing scenarios**:

#### 1. RFQ Candidate Scoring (`rfqCandidates`)

Multi-objective ranking with 4 scoring dimensions + penalties:

| Dimension | Weight (balanced) | Factors |
|-----------|-------------------|---------|
| Lead time | 25% | Transit days, supplier lead time vs. need-by-date |
| Cost | 25% | Unit price benchmarked against cheapest option |
| Risk | 25% | Qualification level, capacity margin, approved status |
| Lane | 25% | Transport reliability, route availability |

Objective presets: `delivery-first`, `cost-first`, `resilience-first`, `balanced`.

Hard-fail detection: unapproved suppliers, insufficient capacity, impossible delivery dates.

#### 2. Single-Source Governance (`singleSourceParts`)

Identify parts with only 1 qualified supplier — supply chain vulnerability detection.

| Bottleneck Part | Sole Supplier | Risk |
|----------------|---------------|------|
| MCU-001 | S1 (TaiwanSemi) | Critical — no alternative |
| CAP-001 | S6 (ShanghaiCaps) | Critical — no alternative |
| DSP-001–004 | S8 (VietnamElec) | Conditional qualification only |

Returns: risk explanation, second-source recommendation, `ALTERNATIVE_TO` relationships from Neo4j.

#### 3. MOQ Consolidation (`consolidatePO`)

Aggregate scattered demand for the same part → meet MOQ thresholds → optimize allocation.

- Allocation policies: `priority` (highest priority orders first), `earliest_due`, `risk_min`
- Rounds up to MOQ multiples, finds best-price supplier
- Returns per-order allocation breakdown with explanation

**GraphQL queries & mutations**:
```graphql
# RFQ ranking
{ rfqCandidates(partId: "P1A", qty: 1000, objective: "balanced") {
    candidates { rank supplierId totalScore breakdown { lead cost risk lane } explanations }
}}

# Single-source check
{ singleSourceParts(threshold: 1) {
    parts { partId supplierCount riskExplanation recommendation }
}}

# MOQ consolidation
{ consolidatePO(partId: "MCU-001", horizonDays: 30) {
    totalDemand consolidatedQty supplierId moq allocations { orderId qty priority }
}}

# Execute PO from RFQ recommendation
mutation { createPOFromRfq(partId: "P1A", supplierId: "S2", qty: 500) {
    success message auditEventId
}}
```

**Chat NL support** (6+ sourcing query types):
- "P1A 有哪些供应商可选？" → RFQ candidates
- "哪些零件只有单一来源？" → single-source governance
- "合并 MCU-001 近30天需求" → MOQ consolidation
- "检查 S8 的资质" → supplier qualification check

## Project Structure

```
demo-foundry-sprint0/
├── docker-compose.yml          # 13 services
├── Makefile                    # up / down / seed / smoke / reset / demo-sprint3
│
├── infra/
│   ├── postgres/
│   │   ├── crm/                # Schema + seed: customers, crm_orders
│   │   ├── erp/                # Schema + seed: suppliers, parts, POs, audit, sourcing
│   │   └── mes/                # Schema + seed: factories, machines, production_orders
│   ├── neo4j/                  # Cypher seeds: ontology, sprint2 extensions, sprint4 sourcing
│   └── trino/etc/catalog/      # CRM, ERP, MES, Iceberg connector configs
│
├── services/
│   ├── graphql-api/            # Apollo + Neo4j + simulation + sourcing + chat (TypeScript)
│   ├── twin-sim/               # What-if simulation engine (Python/FastAPI)
│   ├── agent-api/              # Multi-agent workflow + sourcing scoring (Python/FastAPI)
│   └── control-tower-ui/       # React dashboard (Vite + Apollo Client)
│
├── scripts/
│   ├── smoke.sh                # Full integration test suite
│   ├── run_demo_sprint3.sh     # Sprint 3 end-to-end demo
│   ├── generate_demo_data.py   # Parametric data generator
│   ├── init_minio.sh           # Iceberg bucket setup
│   └── init_iceberg.sh         # Iceberg table creation via Trino
│
└── data/scenarios/             # 5 pre-built scenario JSON files
```

## Smoke Test Coverage

`make smoke` validates the full stack end-to-end:

| Check | Sprint |
|-------|--------|
| Postgres CRM/ERP/MES row counts | 0 |
| Neo4j ontology traversal | 0 |
| Trino statement execution | 0 |
| Nessie catalog config | 0 |
| Iceberg table queries | 1 |
| GraphQL `orders` query | 1 |
| Control Tower UI HTTP 200 | 1 |
| `ordersAtRisk` scenario query | 1 |
| Chat: "风险订单Top10" | 1 |
| Chat: "供应商S1停产影响范围" | 1 |
| Twin-Sim healthz + switch-supplier | 2 |
| GraphQL `simulateSwitchSupplier` mutation | 2 |
| GraphQL `blastRadius` query | 2 |
| Agent-API healthz | 3 |
| `CREATE_PO` → PO count increased | 3 |
| `audit_events` ≥ 1 row | 3 |
| `EXPEDITE_SHIPMENT` success | 3 |
| GraphQL `rfqCandidates` with explanations | 4 |
| GraphQL `singleSourceParts` | 4 |
| Agent-API `rfq-candidates` for MCU-001 | 4 |
| Data scale: ≥10 suppliers, ≥200 parts, ≥100 demands | 4 |
