SHELL := /bin/bash

COMPOSE ?= docker compose

.PHONY: up down ps logs seed smoke reset

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=200

# Seed is idempotent-ish for demo purposes (inserts guarded by ON CONFLICT / MERGE)
seed:
	@echo "==> Seeding Postgres (CRM/ERP/MES) ..."
	$(COMPOSE) exec -T postgres_crm psql -U demo -d crm -f /docker-entrypoint-initdb.d/02_seed.sql
	$(COMPOSE) exec -T postgres_erp psql -U demo -d erp -f /docker-entrypoint-initdb.d/02_seed.sql
	$(COMPOSE) exec -T postgres_mes psql -U demo -d mes -f /docker-entrypoint-initdb.d/02_seed.sql
	@echo "==> Seeding Neo4j Ontology graph ..."
	$(COMPOSE) exec -T neo4j cypher-shell -u neo4j -p demo12345 -f /import/seed.cypher
	@echo "==> (Optional) Create a demo Debezium connector ..."
	@echo "    Run: bash scripts/register_debezium_connectors.sh"

smoke:
	bash scripts/smoke.sh

reset:
	$(COMPOSE) down -v
	$(COMPOSE) up -d
	@echo "Waiting a bit for services..."
	sleep 10
	$(MAKE) seed
	$(MAKE) smoke
