#!/usr/bin/env bash
set -euo pipefail

echo "=== Twin-Sim Smoke Tests ==="

echo "==> 1. Twin-Sim /healthz ..."
curl -fsS http://localhost:7100/healthz | python3 -c "import sys,json; assert json.load(sys.stdin)['status']=='ok'; print('    OK')"

echo "==> 2. POST /simulate/switch-supplier ..."
curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"orderId":"SO1001","partId":"P1A","toSupplierId":"S2"}' \
  http://localhost:7100/simulate/switch-supplier | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert len(d['scenarios']) == 3, f'Expected 3 scenarios, got {len(d[\"scenarios\"])}'
assert d['recommended'] in ('A','B','C'), f'Bad recommended: {d[\"recommended\"]}'
assert d['blastRadius']['impactedParts'], 'No impacted parts'
for s in d['scenarios']:
    print(f'    {s[\"label\"]}: {s[\"description\"]} | ETA Δ{s[\"eta_delta_days\"]}d | cost Δ{s[\"cost_delta_pct\"]}% | LS={s[\"line_stop_risk\"]} | QR={s[\"quality_risk\"]}')
print(f'    Recommended: {d[\"recommended\"]}')
"

echo "==> 3. POST /simulate/change-lane ..."
curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"orderId":"SO1001","partId":"P1A","supplierId":"S1","toLane":"Air"}' \
  http://localhost:7100/simulate/change-lane | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert len(d['scenarios']) == 3
print(f'    3 scenarios, recommended={d[\"recommended\"]}')
"

echo "==> 4. POST /simulate/transfer-factory ..."
curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"orderId":"SO1001","toFactoryId":"F3"}' \
  http://localhost:7100/simulate/transfer-factory | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert len(d['scenarios']) == 3
print(f'    3 scenarios, recommended={d[\"recommended\"]}')
"

echo "==> 5. GET /blast-radius?orderId=SO1001 ..."
curl -fsS 'http://localhost:7100/blast-radius?orderId=SO1001' | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    Parts: {len(d[\"impactedParts\"])}, Factories: {len(d[\"impactedFactories\"])}, Paths: {len(d[\"paths\"])}')
"

echo "==> 6. GraphQL simulateSwitchSupplier ..."
curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"mutation { simulateSwitchSupplier(orderId:\"SO1001\", partId:\"P1A\", toSupplierId:\"S2\") { scenarios { label description eta_delta_days cost_delta_pct line_stop_risk quality_risk } recommended assumptions } }"}' \
  http://localhost:4000/graphql | python3 -c "
import sys, json
d = json.load(sys.stdin)
sim = d['data']['simulateSwitchSupplier']
assert len(sim['scenarios']) == 3
assert sim['recommended']
print(f'    GraphQL mutation OK, recommended={sim[\"recommended\"]}')
"

echo "==> 7. GraphQL blastRadius ..."
curl -fsS -X POST -H 'Content-Type: application/json' \
  --data '{"query":"{ blastRadius(orderId:\"SO1001\") { impactedOrders { id } impactedParts { id name } impactedFactories { id name } paths { from relation to } } }"}' \
  http://localhost:4000/graphql | python3 -c "
import sys, json
d = json.load(sys.stdin)
br = d['data']['blastRadius']
print(f'    Orders: {len(br[\"impactedOrders\"])}, Parts: {len(br[\"impactedParts\"])}, Factories: {len(br[\"impactedFactories\"])}')
"

echo "=== All Twin-Sim smoke tests passed. ==="
