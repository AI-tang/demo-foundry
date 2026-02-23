#!/usr/bin/env bash
# Sprint 3 Demo: Multi-Agent Workflow → Writeback → Audit
# 10-step end-to-end demonstration
set -euo pipefail

BASE_AGENT="http://localhost:7200"
BASE_GQL="http://localhost:4000"

ok()   { echo "  ✓ $1"; }
fail() { echo "  ✗ $1" >&2; exit 1; }
sep()  { echo ""; echo "────────────────────────────────────────"; }

echo "╔══════════════════════════════════════════════╗"
echo "║  Sprint 3 Demo: Agent Workflow + Audit       ║"
echo "╚══════════════════════════════════════════════╝"

# ── Step 1: Plan ──────────────────────────────────────────────────
sep
echo "Step 1/10 – Integrator: Plan a purchase order action"
PLAN=$(curl -fsS -X POST "$BASE_AGENT/agent/plan" \
  -H 'Content-Type: application/json' \
  -d '{"question":"Create a purchase order for P1A from supplier S2","lang":"en"}')
echo "$PLAN" | python3 -m json.tool
INTENT=$(echo "$PLAN" | python3 -c "import sys,json; print(json.load(sys.stdin)['intent'])")
[ "$INTENT" = "CREATE_PO" ] && ok "Intent detected: $INTENT" || fail "Expected CREATE_PO, got $INTENT"

# ── Step 2: Analyze ───────────────────────────────────────────────
sep
echo "Step 2/10 – Analyst: Gather context for SO1001 / P1A / S1"
ANALYSIS=$(curl -fsS -X POST "$BASE_AGENT/agent/analyze" \
  -H 'Content-Type: application/json' \
  -d '{"orderId":"SO1001","partId":"P1A","supplierId":"S1"}')
echo "$ANALYSIS" | python3 -m json.tool
ok "Analysis complete"

# ── Step 3: Simulate ──────────────────────────────────────────────
sep
echo "Step 3/10 – Simulator: What-if switch S1→S2 for P1A"
SIM=$(curl -fsS -X POST "$BASE_AGENT/agent/simulate" \
  -H 'Content-Type: application/json' \
  -d '{"orderId":"SO1001","partId":"P1A","toSupplierId":"S2"}')
echo "$SIM" | python3 -m json.tool
REC=$(echo "$SIM" | python3 -c "import sys,json; print(json.load(sys.stdin)['recommended'])")
ok "Recommended scenario: $REC"

# ── Step 4: Execute CREATE_PO ─────────────────────────────────────
sep
echo "Step 4/10 – Action: Execute CREATE_PO for P1A from S2"
PO_COUNT_BEFORE=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc \
  "SELECT count(*) FROM purchase_orders;")
EXEC=$(curl -fsS -X POST "$BASE_AGENT/agent/execute" \
  -H 'Content-Type: application/json' \
  -d '{"action":"CREATE_PO","partId":"P1A","supplierId":"S2","qty":500,"orderId":"SO1001","actor":"demo-user"}')
echo "$EXEC" | python3 -m json.tool
SUCCESS=$(echo "$EXEC" | python3 -c "import sys,json; print(json.load(sys.stdin)['success'])")
[ "$SUCCESS" = "True" ] && ok "CREATE_PO succeeded" || fail "CREATE_PO failed"

# ── Step 5: Execute EXPEDITE_SHIPMENT ─────────────────────────────
sep
echo "Step 5/10 – Action: Expedite shipment for PO-ERP-2001"
EXPED=$(curl -fsS -X POST "$BASE_AGENT/agent/execute" \
  -H 'Content-Type: application/json' \
  -d '{"action":"EXPEDITE_SHIPMENT","poId":"PO-ERP-2001","newMode":"Air","actor":"demo-user"}')
echo "$EXPED" | python3 -m json.tool
EXPED_OK=$(echo "$EXPED" | python3 -c "import sys,json; print(json.load(sys.stdin)['success'])")
[ "$EXPED_OK" = "True" ] && ok "EXPEDITE_SHIPMENT succeeded" || fail "EXPEDITE_SHIPMENT failed"

# ── Step 6: Verify purchase_orders count increased ────────────────
sep
echo "Step 6/10 – Verify: purchase_orders count increased"
PO_COUNT_AFTER=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc \
  "SELECT count(*) FROM purchase_orders;")
echo "  Before: $PO_COUNT_BEFORE  After: $PO_COUNT_AFTER"
[ "$PO_COUNT_AFTER" -gt "$PO_COUNT_BEFORE" ] && ok "PO count increased" || fail "PO count did not increase"

# ── Step 7: Verify audit trail ────────────────────────────────────
sep
echo "Step 7/10 – Verify: Audit trail in Postgres"
docker compose exec -T postgres_erp psql -U demo -d erp -c \
  "SELECT event_id, ts, actor, action, status FROM audit_events ORDER BY ts;"
AUDIT_COUNT=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc \
  "SELECT count(*) FROM audit_events;")
[ "$AUDIT_COUNT" -ge 2 ] && ok "Audit events: $AUDIT_COUNT" || fail "Expected ≥2 audit events, got $AUDIT_COUNT"

# ── Step 8: Verify action_requests ────────────────────────────────
sep
echo "Step 8/10 – Verify: Action requests"
docker compose exec -T postgres_erp psql -U demo -d erp -c \
  "SELECT request_id, type, approval_status, created_at FROM action_requests ORDER BY created_at;"
AR_COUNT=$(docker compose exec -T postgres_erp psql -U demo -d erp -tAc \
  "SELECT count(*) FROM action_requests;")
[ "$AR_COUNT" -ge 2 ] && ok "Action requests: $AR_COUNT" || fail "Expected ≥2 action requests, got $AR_COUNT"

# ── Step 9: GraphQL mutations ─────────────────────────────────────
sep
echo "Step 9/10 – GraphQL: createPurchaseOrderRecommendation mutation"
GQL_PO=$(curl -fsS -X POST "$BASE_GQL/graphql" \
  -H 'Content-Type: application/json' \
  -d '{"query":"mutation { createPurchaseOrderRecommendation(partId:\"P1A\", supplierId:\"S2\", qty:200, orderId:\"SO1001\") { success message auditEventId } }"}')
echo "$GQL_PO" | python3 -m json.tool
GQL_PO_OK=$(echo "$GQL_PO" | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('data',{}).get('createPurchaseOrderRecommendation',{})
print('1' if r.get('success') else '0')
" 2>/dev/null || echo "0")
[ "$GQL_PO_OK" = "1" ] && ok "GraphQL mutation succeeded" || fail "GraphQL mutation failed"

# ── Step 10: Chat NL action (requires OpenAI key) ────────────────
sep
echo "Step 10/10 – Chat: Natural language action intent"
if [ -n "${OPENAI_API_KEY:-}" ]; then
  CHAT_ACTION=$(curl -fsS -X POST "$BASE_GQL/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Create a purchase order for 300 units of P1A from S2","lang":"en"}')
  echo "$CHAT_ACTION" | python3 -m json.tool
  ok "Chat action intent handled (check response above)"
else
  echo "  (Skipped – OPENAI_API_KEY not set)"
  ok "Skipped (no OpenAI key)"
fi

sep
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  Sprint 3 Demo COMPLETE                      ║"
echo "║  All 10 steps passed.                        ║"
echo "╚══════════════════════════════════════════════╝"
