SHELL := /bin/bash

COMPOSE ?= docker compose

.PHONY: up down ps logs seed gen-data init-minio init-iceberg smoke sim-smoke reset demo-sprint3

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=200

# Create the MinIO bucket for Iceberg warehouse
init-minio:
	bash scripts/init_minio.sh

# Create Iceberg tables from Postgres data via Trino
init-iceberg:
	bash scripts/init_iceberg.sh

# Generate parametric demo data (scenarios + seed files)
gen-data:
	python3 scripts/generate_demo_data.py

# Seed is idempotent-ish for demo purposes (inserts guarded by ON CONFLICT / MERGE)
seed:
	@echo "==> Seeding Postgres (CRM/ERP/MES) ..."
	$(COMPOSE) exec -T postgres_crm psql -U demo -d crm -f /docker-entrypoint-initdb.d/02_seed.sql
	$(COMPOSE) exec -T postgres_erp psql -U demo -d erp -f /docker-entrypoint-initdb.d/02_seed.sql
	$(COMPOSE) exec -T postgres_mes psql -U demo -d mes -f /docker-entrypoint-initdb.d/02_seed.sql
	@if [ -f infra/postgres/crm/03_seed_generated.sql ]; then \
		echo "==> Seeding generated CRM data ..."; \
		$(COMPOSE) exec -T postgres_crm psql -U demo -d crm -f /docker-entrypoint-initdb.d/03_seed_generated.sql; \
	fi
	@if [ -f infra/postgres/erp/03_seed_generated.sql ]; then \
		echo "==> Seeding generated ERP data ..."; \
		$(COMPOSE) exec -T postgres_erp psql -U demo -d erp -f /docker-entrypoint-initdb.d/03_seed_generated.sql; \
	fi
	@if [ -f infra/postgres/mes/03_seed_generated.sql ]; then \
		echo "==> Seeding generated MES data ..."; \
		$(COMPOSE) exec -T postgres_mes psql -U demo -d mes -f /docker-entrypoint-initdb.d/03_seed_generated.sql; \
	fi
	@echo "==> Seeding Neo4j Ontology graph ..."
	$(COMPOSE) exec -T neo4j cypher-shell -u neo4j -p demo12345 -f /import/seed.cypher
	@if [ -f infra/neo4j/seed_generated.cypher ]; then \
		echo "==> Seeding generated Neo4j data ..."; \
		$(COMPOSE) exec -T neo4j cypher-shell -u neo4j -p demo12345 -f /import/seed_generated.cypher; \
	fi
	@echo "==> Initialising MinIO bucket ..."
	$(MAKE) init-minio
	@echo "==> Creating Iceberg tables ..."
	$(MAKE) init-iceberg
	@echo "==> Seeding Sprint 2 data (Twin-Sim extensions) ..."
	$(COMPOSE) exec -T neo4j cypher-shell -u neo4j -p demo12345 -f /import/seed_sprint2.cypher
	@echo "==> Seeding Sprint 3 schema (audit + action_requests) ..."
	$(COMPOSE) exec -T postgres_erp psql -U demo -d erp -f /docker-entrypoint-initdb.d/04_sprint3_schema.sql
	@echo "==> Seeding Sprint 4 data (sourcing: suppliers, parts, demand, quotes, transport_lanes) ..."
	$(COMPOSE) exec -T postgres_erp psql -U demo -d erp -f /docker-entrypoint-initdb.d/05_sprint4_schema.sql
	@echo "==> Seeding Sprint 4 Neo4j (sourcing graph extensions) ..."
	$(COMPOSE) exec -T neo4j cypher-shell -u neo4j -p demo12345 -f /import/seed_sprint4.cypher
	@echo "==> (Optional) Create a demo Debezium connector ..."
	@echo "    Run: bash scripts/register_debezium_connectors.sh"

smoke:
	bash scripts/smoke.sh

sim-smoke:
	bash scripts/sim_smoke.sh

demo-sprint3:
	bash scripts/run_demo_sprint3.sh

reset:
	$(COMPOSE) down -v
	$(COMPOSE) up -d
	@echo "Waiting a bit for services..."
	sleep 10
	$(MAKE) seed
	$(MAKE) smoke
