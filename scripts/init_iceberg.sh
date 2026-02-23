#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating Iceberg tables from Postgres data via Trino..."

TRINO_URL="http://localhost:8080/v1/statement"
TRINO_HEADERS=(-H 'X-Trino-User: demo' -H 'X-Trino-Catalog: iceberg' -H 'X-Trino-Schema: warehouse')

run_trino() {
  local sql="$1"
  echo "    Running: ${sql:0:80}..."
  local next_uri
  next_uri=$(curl -fsS -X POST "${TRINO_HEADERS[@]}" --data "$sql" "$TRINO_URL" | jq -r '.nextUri // empty')
  # Poll until complete
  while [ -n "$next_uri" ]; do
    local resp
    resp=$(curl -fsS "$next_uri")
    local state
    state=$(echo "$resp" | jq -r '.stats.state // "RUNNING"')
    local error
    error=$(echo "$resp" | jq -r '.error.message // empty')
    if [ -n "$error" ]; then
      echo "    ERROR: $error"
      return 1
    fi
    if [ "$state" = "FINISHED" ]; then
      echo "    Done."
      return 0
    fi
    next_uri=$(echo "$resp" | jq -r '.nextUri // empty')
    sleep 1
  done
  echo "    Done."
}

# Create schema
run_trino "CREATE SCHEMA IF NOT EXISTS iceberg.warehouse"

# --- Orders: JOIN of CRM orders + MES production orders ---
run_trino "DROP TABLE IF EXISTS iceberg.warehouse.orders"
run_trino "
CREATE TABLE iceberg.warehouse.orders AS
SELECT
  c.crm_order_id   AS order_id,
  c.customer_id,
  c.order_date,
  c.status          AS crm_status,
  m.prod_order_id,
  m.factory_id,
  m.product_id,
  m.qty,
  m.status          AS mes_status,
  m.planned_start,
  m.planned_end
FROM crm.public.crm_orders c
LEFT JOIN mes.public.production_orders m
  ON m.sales_order_id = c.crm_order_id
"

# --- Supply chain: Denormalized suppliers + parts + inventory ---
run_trino "DROP TABLE IF EXISTS iceberg.warehouse.supply_chain"
run_trino "
CREATE TABLE iceberg.warehouse.supply_chain AS
SELECT
  s.supplier_id,
  s.name            AS supplier_name,
  s.approved,
  p.part_id,
  p.name            AS part_name,
  p.part_type,
  sp.priority,
  sp.lead_time_days,
  il.lot_id,
  il.on_hand,
  il.reserved,
  il.location
FROM erp.public.suppliers s
JOIN erp.public.supplier_parts sp ON sp.supplier_id = s.supplier_id
JOIN erp.public.parts p           ON p.part_id      = sp.part_id
LEFT JOIN erp.public.inventory_lots il ON il.part_id = p.part_id
"

echo "==> Iceberg tables created successfully."
echo "    - iceberg.warehouse.orders"
echo "    - iceberg.warehouse.supply_chain"
