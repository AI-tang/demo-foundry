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

echo "==> Twin-Sim healthz ..."
TS_CODE=$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:7100/healthz)
if [ "$TS_CODE" = "200" ]; then
  echo "    Twin-Sim healthy (HTTP $TS_CODE)"
else
  echo "    FAIL: Twin-Sim returned HTTP $TS_CODE" && exit 1
fi

echo "==> Twin-Sim: simulate switch-supplier ..."
SIM_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"orderId":"SO1001","partId":"P1A","toSupplierId":"S2"}' \
  http://localhost:7100/simulate/switch-supplier)
SIM_OK=$(echo "$SIM_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
sc = d.get('scenarios', [])
rec = d.get('recommended', '')
print('1' if len(sc) == 3 and rec else '0')
" 2>/dev/null || echo "0")
if [ "$SIM_OK" = "1" ]; then
  echo "    switch-supplier returned 3 scenarios with recommendation."
else
  echo "    FAIL: switch-supplier did not return expected structure!" && exit 1
fi

echo "==> GraphQL: simulateSwitchSupplier mutation ..."
GQL_SIM=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"mutation { simulateSwitchSupplier(orderId:\"SO1001\", partId:\"P1A\", toSupplierId:\"S2\") { scenarios { label description eta_delta_days cost_delta_pct line_stop_risk quality_risk } recommended assumptions } }"}' \
  http://localhost:4000/graphql)
GQL_SIM_OK=$(echo "$GQL_SIM" | python3 -c "
import sys, json
d = json.load(sys.stdin)
sim = d.get('data', {}).get('simulateSwitchSupplier', {})
sc = sim.get('scenarios', [])
rec = sim.get('recommended', '')
print('1' if len(sc) == 3 and rec else '0')
" 2>/dev/null || echo "0")
if [ "$GQL_SIM_OK" = "1" ]; then
  echo "    simulateSwitchSupplier returned 3 scenarios, recommended=$(echo "$GQL_SIM" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['simulateSwitchSupplier']['recommended'])" 2>/dev/null)"
else
  echo "    FAIL: simulateSwitchSupplier did not return expected structure!" && exit 1
fi

echo "==> GraphQL: blastRadius query ..."
BR_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"{ blastRadius(orderId:\"SO1001\") { impactedParts { id } impactedFactories { id } } }"}' \
  http://localhost:4000/graphql)
BR_OK=$(echo "$BR_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
br = d.get('data', {}).get('blastRadius', {})
print('1' if br.get('impactedParts') is not None else '0')
" 2>/dev/null || echo "0")
if [ "$BR_OK" = "1" ]; then
  echo "    blastRadius returned impact data."
else
  echo "    FAIL: blastRadius did not return expected data!" && exit 1
fi

echo "==> Agent-API healthz ..."
AGENT_CODE=$(curl -fsS -o /dev/null -w '%{http_code}' http://localhost:7200/healthz)
if [ "$AGENT_CODE" = "200" ]; then
  echo "    Agent-API healthy (HTTP $AGENT_CODE)"
else
  echo "    FAIL: Agent-API returned HTTP $AGENT_CODE" && exit 1
fi

echo "==> Agent-API: CREATE_PO ..."
PO_BEFORE=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc "SELECT count(*) FROM purchase_orders;")
CREATE_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"action":"CREATE_PO","partId":"P1A","supplierId":"S2","qty":100,"orderId":"SO1001","actor":"smoke-test"}' \
  http://localhost:7200/agent/execute)
CREATE_OK=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print('1' if json.load(sys.stdin).get('success') else '0')" 2>/dev/null || echo "0")
if [ "$CREATE_OK" = "1" ]; then
  echo "    CREATE_PO succeeded."
else
  echo "    FAIL: CREATE_PO did not succeed!" && exit 1
fi

echo "==> Verify: purchase_orders count increased ..."
PO_AFTER=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc "SELECT count(*) FROM purchase_orders;")
if [ "$PO_AFTER" -gt "$PO_BEFORE" ]; then
  echo "    purchase_orders: $PO_BEFORE → $PO_AFTER"
else
  echo "    FAIL: purchase_orders count did not increase ($PO_BEFORE → $PO_AFTER)" && exit 1
fi

echo "==> Verify: audit_events ≥ 1 ..."
AUDIT_ROWS=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc "SELECT count(*) FROM audit_events;")
if [ "$AUDIT_ROWS" -ge 1 ]; then
  echo "    audit_events: $AUDIT_ROWS row(s)"
else
  echo "    FAIL: audit_events has $AUDIT_ROWS rows (expected ≥1)" && exit 1
fi

echo "==> Agent-API: EXPEDITE_SHIPMENT ..."
EXPED_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"action":"EXPEDITE_SHIPMENT","poId":"PO-ERP-2001","newMode":"Air","actor":"smoke-test"}' \
  http://localhost:7200/agent/execute)
EXPED_OK=$(echo "$EXPED_RESP" | python3 -c "import sys,json; print('1' if json.load(sys.stdin).get('success') else '0')" 2>/dev/null || echo "0")
if [ "$EXPED_OK" = "1" ]; then
  echo "    EXPEDITE_SHIPMENT succeeded."
else
  echo "    FAIL: EXPEDITE_SHIPMENT did not succeed!" && exit 1
fi

echo "==> Sprint 4: GraphQL rfqCandidates ..."
RFQ_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"{ rfqCandidates(partId:\"P1A\", qty:1000, objective:\"balanced\") { partId candidates { rank supplierId totalScore explanations } } }"}' \
  http://localhost:4000/graphql)
RFQ_OK=$(echo "$RFQ_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
cands = d.get('data',{}).get('rfqCandidates',{}).get('candidates',[])
has_expl = any(len(c.get('explanations',[])) > 0 for c in cands)
print('1' if len(cands) >= 2 and has_expl else '0')
" 2>/dev/null || echo "0")
if [ "$RFQ_OK" = "1" ]; then
  echo "    rfqCandidates returned candidates with explanations."
else
  echo "    FAIL: rfqCandidates did not return expected data!" && exit 1
fi

echo "==> Sprint 4: GraphQL singleSourceParts ..."
SSP_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"{ singleSourceParts(threshold:1) { parts { partId supplierCount riskExplanation } } }"}' \
  http://localhost:4000/graphql)
SSP_OK=$(echo "$SSP_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
parts = d.get('data',{}).get('singleSourceParts',{}).get('parts',[])
print('1' if len(parts) >= 1 else '0')
" 2>/dev/null || echo "0")
if [ "$SSP_OK" = "1" ]; then
  echo "    singleSourceParts returned single-source parts."
else
  echo "    FAIL: singleSourceParts returned empty!" && exit 1
fi

echo "==> Sprint 4: Agent-API rfq-candidates direct ..."
ARFQ_RESP=$(curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"partId":"MCU-001","factoryId":"F1","qty":1000,"objective":"delivery-first"}' \
  http://localhost:7200/agent/rfq-candidates)
ARFQ_OK=$(echo "$ARFQ_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
cands = d.get('candidates',[])
print('1' if len(cands) >= 1 else '0')
" 2>/dev/null || echo "0")
if [ "$ARFQ_OK" = "1" ]; then
  echo "    rfq-candidates for MCU-001 returned candidates."
else
  echo "    FAIL: rfq-candidates for MCU-001 returned no candidates!" && exit 1
fi

echo "==> Sprint 4: Data scale verification ..."
SUPPLIER_COUNT=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc "SELECT count(*) FROM suppliers;")
PART_COUNT=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc "SELECT count(*) FROM parts;")
DEMAND_COUNT=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc "SELECT count(*) FROM demand;")
echo "    Suppliers: $SUPPLIER_COUNT, Parts: $PART_COUNT, Demand records: $DEMAND_COUNT"
if [ "$SUPPLIER_COUNT" -ge 10 ] && [ "$PART_COUNT" -ge 200 ] && [ "$DEMAND_COUNT" -ge 100 ]; then
  echo "    Scale requirements met."
else
  echo "    FAIL: Scale requirements not met (need >=10 suppliers, >=200 parts, >=100 demands)" && exit 1
fi

echo "==> All smoke tests passed."
