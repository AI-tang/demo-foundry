#!/usr/bin/env bash
set -euo pipefail

# Registers a simple Debezium connector for CRM Postgres.
# Note: This is OPTIONAL for Sprint 0, but included to show CDC path.

CONNECT_URL="http://localhost:8083/connectors"

payload=$(cat <<'JSON'
{
  "name": "crm-postgres-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "postgres_crm",
    "database.port": "5432",
    "database.user": "demo",
    "database.password": "demo",
    "database.dbname": "crm",
    "topic.prefix": "crm",
    "schema.include.list": "public",
    "table.include.list": "public.crm_orders",
    "plugin.name": "pgoutput",
    "publication.autocreate.mode": "filtered",
    "slot.name": "crm_slot",
    "tombstones.on.delete": "false"
  }
}
JSON
)

echo "==> Registering Debezium connector..."
curl -fsS -X POST -H "Content-Type: application/json" --data "$payload" "${CONNECT_URL}" | jq .
echo "==> Done. Check connectors:"
curl -fsS "${CONNECT_URL}" | jq .
