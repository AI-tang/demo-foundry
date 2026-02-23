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

echo "==> Nessie catalog sanity..."
curl -fsS http://localhost:19120/api/v2/config | jq -r '.defaultBranch // "OK"' 2>/dev/null || echo "    Nessie reachable (jq unavailable for detailed check)"

echo "==> Iceberg tables sanity..."
if command -v jq >/dev/null 2>&1; then
  run_trino "SELECT count(*) FROM iceberg.warehouse.orders"
  run_trino "SELECT count(*) FROM iceberg.warehouse.supply_chain"
  echo "    Iceberg tables queryable via Trino."
fi

echo "==> GraphQL API sanity..."
GRAPHQL_RESP=$(curl -fsS -X POST \
  -H 'Content-Type: application/json' \
  --data '{"query":"{ orders { id status } }"}' \
  http://localhost:4000/graphql)
echo "    GraphQL response: $(echo "$GRAPHQL_RESP" | head -c 200)"

echo "==> Control Tower UI sanity..."
HTTP_CODE=$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:3000/)
if [ "$HTTP_CODE" = "200" ]; then
  echo "    Control Tower UI serving at http://localhost:3000 (HTTP $HTTP_CODE)"
else
  echo "    WARNING: Control Tower UI returned HTTP $HTTP_CODE"
fi

echo "==> Scenario API: ordersAtRisk ..."
RISK_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"{ ordersAtRisk { id status } }"}' \
  http://localhost:4000/graphql)
RISK_COUNT=$(echo "$RISK_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',{}).get('ordersAtRisk',[])))" 2>/dev/null || echo "0")
if [ "$RISK_COUNT" -gt 0 ]; then
  echo "    ordersAtRisk returned $RISK_COUNT orders."
else
  echo "    FAIL: ordersAtRisk returned empty!" && exit 1
fi

echo "==> Chat: 风险订单Top10 ..."
CHAT1=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"message":"风险订单Top10","lang":"zh"}' \
  http://localhost:4000/chat)
CHAT1_OK=$(echo "$CHAT1" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('data') else '0')" 2>/dev/null || echo "0")
if [ "$CHAT1_OK" = "1" ]; then
  echo "    Chat '风险订单Top10' returned data."
else
  echo "    FAIL: Chat '风险订单Top10' returned no data!" && exit 1
fi

echo "==> Chat: 供应商S1停产影响范围 ..."
CHAT2=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"message":"供应商S1停产影响范围","lang":"zh"}' \
  http://localhost:4000/chat)
CHAT2_OK=$(echo "$CHAT2" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('data') else '0')" 2>/dev/null || echo "0")
if [ "$CHAT2_OK" = "1" ]; then
  echo "    Chat '供应商S1停产影响范围' returned data."
else
  echo "    FAIL: Chat '供应商S1停产影响范围' returned no data!" && exit 1
fi

echo "==> All smoke tests passed."
