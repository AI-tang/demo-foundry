#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking container health..."
docker compose ps

echo "==> Postgres CRM sanity..."
docker compose exec -T postgres_crm psql -U demo -d crm -c "SELECT count(*) AS crm_orders FROM crm_orders;"

echo "==> Postgres ERP sanity..."
docker compose exec -T postgres_erp psql -U demo -d erp -c "SELECT count(*) AS purchase_orders FROM purchase_orders;"

echo "==> Postgres MES sanity..."
docker compose exec -T postgres_mes psql -U demo -d mes -c "SELECT count(*) AS production_orders FROM production_orders;"

echo "==> Neo4j sanity (Orders -> Required Parts -> Suppliers)..."
docker compose exec -T neo4j cypher-shell -u neo4j -p demo12345 "
MATCH (o:Order {id:'SO1001'})-[:REQUIRES]->(p:Part)<-[:SUPPLIES]-(s:Supplier)
RETURN o.id AS order, collect(distinct p.id) AS parts, collect(distinct s.id) AS suppliers;"

echo "==> Trino sanity (query Postgres catalogs)..."
# Trino uses basic auth disabled by default; curl a trivial query via HTTP
# Use /v1/statement endpoint
CRM_QUERY="SELECT crm_order_id, status FROM crm.public.crm_orders ORDER BY crm_order_id"
ERP_QUERY="SELECT po_id, status FROM erp.public.purchase_orders ORDER BY po_id"
MES_QUERY="SELECT prod_order_id, status FROM mes.public.production_orders ORDER BY prod_order_id"

run_trino () {
  local q="$1"
  curl -fsS -X POST \
    -H 'X-Trino-User: demo' \
    -H 'X-Trino-Catalog: crm' \
    -H 'X-Trino-Schema: public' \
    --data "$q" \
    http://localhost:8080/v1/statement | jq -r '.id' >/dev/null
}

if command -v jq >/dev/null 2>&1; then
  echo "    Trino reachable and accepts statements (requires jq for full result parsing)."
  run_trino "$CRM_QUERY"
else
  echo "    jq not found; skipping Trino statement parsing. Trino UI should still be reachable at http://localhost:8080"
fi

echo "✅ Smoke tests passed."
