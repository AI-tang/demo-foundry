# demo-foundry (Sprint 0) — macOS quickstart

This is the **Sprint 0** initial version of a Palantir-like demo stack:
- 3 mock source systems: **CRM / ERP / MES** (Postgres)
- **Kafka + Debezium** for CDC
- **Neo4j** for ontology graph (great visualization)
- **MinIO + Trino** for query engine (Sprint 0 uses Postgres catalogs; Iceberg-on-MinIO added in Sprint 1)

## Prereqs (macOS)
- Docker Desktop (running)
- `make` (Xcode CLT usually provides it)

## Start
```bash
cd demo-foundry-sprint0
make up
make seed
make smoke
```

## Useful URLs
- Neo4j Browser: http://localhost:7474  (user: neo4j / pass: demo12345)
- Trino UI: http://localhost:8080
- MinIO Console: http://localhost:9001 (user: minio / pass: minio12345)
- Debezium Connect: http://localhost:8083

## What’s inside
- `infra/postgres/*`: schema + seed for each system
- `infra/neo4j/seed.cypher`: ontology seed (multi-factory, multi-supplier, multi-level BOM)
- `infra/trino/etc/catalog/*.properties`: Trino catalogs for crm/erp/mes
- `scripts/smoke.sh`: basic health + sample queries

## Next (Sprint 1 ideas)
- Add Iceberg catalog on MinIO (needs metastore or REST catalog)
- Add GraphQL-first API using `@neo4j/graphql` and an Apollo server
- Add a “control tower” UI and agent orchestrator
