#!/usr/bin/env python3
"""
Parametric demo-data generator for the Supply Chain Control Tower.
Reads scenario injections from data/scenarios/*.json and produces:
  - infra/postgres/crm/03_seed_generated.sql
  - infra/postgres/erp/03_seed_generated.sql
  - infra/postgres/mes/03_seed_generated.sql
  - infra/neo4j/seed_generated.cypher
Python 3 stdlib only.
"""

import json
import os
import random
from datetime import date, timedelta
from pathlib import Path

# ── Parameters ──────────────────────────────────────────────────────
NUM_FACTORIES = 3
NUM_SUPPLIERS = 10
NUM_PRODUCTS = 20
NUM_PARTS = 200        # 40 ASSEMBLY + 160 COMPONENT
NUM_ORDERS = 100
BOM_DEPTH_MIN = 3
BOM_DEPTH_MAX = 5

SEED = 42
random.seed(SEED)

ROOT = Path(__file__).resolve().parent.parent
SCENARIOS_DIR = ROOT / "data" / "scenarios"

# ── Helpers ─────────────────────────────────────────────────────────

def sql_str(v):
    """Escape a string value for SQL."""
    if v is None:
        return "NULL"
    return "'" + str(v).replace("'", "''") + "'"

def sql_bool(v):
    return "true" if v else "false"

def sql_date(d):
    if d is None:
        return "NULL"
    return f"'{d}'"

def rand_date(start, end):
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, max(delta, 1)))

def cypher_str(v):
    return "'" + str(v).replace("'", "\\'").replace("\\", "\\\\") + "'"


# ── Load scenarios ──────────────────────────────────────────────────

def load_scenarios():
    scenarios = []
    if SCENARIOS_DIR.is_dir():
        for f in sorted(SCENARIOS_DIR.glob("*.json")):
            scenarios.append(json.loads(f.read_text(encoding="utf-8")))
    return scenarios

scenarios = load_scenarios()

# Collect scenario overrides
scenario_orders_at_risk = set()
scenario_parts_shortage = {}   # part_id -> {on_hand, reserved}
scenario_risk_events = []
scenario_defects = []
scenario_ecos = []
scenario_status_conflicts = {}  # order_id -> {crm, sap, mes}
scenario_quality_hold_orders = set()
scenario_alternative_suppliers = []  # [{from, to}]

for sc in scenarios:
    inj = sc.get("inject", {})
    for oid in inj.get("orders_at_risk", []):
        scenario_orders_at_risk.add(oid)
    for ps in inj.get("parts_shortage", []):
        scenario_parts_shortage[ps["part"]] = ps
    for re in inj.get("risk_events", []):
        scenario_risk_events.append(re)
    for d in inj.get("defects", []):
        scenario_defects.append(d)
    for e in inj.get("ecos", []):
        scenario_ecos.append(e)
    for sc_conf in inj.get("status_conflicts", []):
        scenario_status_conflicts[sc_conf["order"]] = sc_conf
    for oid in inj.get("quality_hold_orders", []):
        scenario_quality_hold_orders.add(oid)
    for alt in inj.get("alternative_suppliers", []):
        scenario_alternative_suppliers.append(alt)

# ── Generate base data ──────────────────────────────────────────────

# Factories
factory_names = ["上海工厂 / Shanghai Plant", "苏州工厂 / Suzhou Plant", "重庆工厂 / Chongqing Plant"]
factories = []
for i in range(NUM_FACTORIES):
    fid = f"F{i+1}"
    factories.append({"id": fid, "name": factory_names[i] if i < len(factory_names) else f"Factory-{i+1}"})

# Factory backup pairs
factory_backups = [("F1", "F3"), ("F2", "F3")]

# Suppliers
supplier_names = [
    "台芯科技 / TaiwanChipCo",
    "韩芯备份 / KoreaChipBackup",
    "日本传感 / JapanSensor",
    "苏州电路 / SuzhouPCB",
    "深圳电源 / ShenzhenPower",
    "东莞精密 / DongguanPrecision",
    "武汉光电 / WuhanOptoelectronics",
    "成都航电 / ChengduAvionics",
    "天津材料 / TianjinMaterials",
    "杭州软控 / HangzhouSoftControl",
]
suppliers = []
for i in range(NUM_SUPPLIERS):
    sid = f"S{i+1}"
    suppliers.append({"id": sid, "name": supplier_names[i] if i < len(supplier_names) else f"Supplier-{i+1}"})

# Parts: 40 ASSEMBLY + 160 COMPONENT
assemblies = []
components = []
all_parts = []

for i in range(1, 41):
    pid = f"P{i:03d}"
    assemblies.append({"id": pid, "name": f"组件-{pid} / Assembly-{pid}", "partType": "ASSEMBLY"})

for i in range(41, NUM_PARTS + 1):
    pid = f"P{i:03d}"
    components.append({"id": pid, "name": f"零件-{pid} / Component-{pid}", "partType": "COMPONENT"})

all_parts = assemblies + components

# Products
products = []
for i in range(1, NUM_PRODUCTS + 1):
    prid = f"PR{i}"
    products.append({"id": prid, "name": f"产品-{prid} / Product-{prid}"})

# BOM: product -> assemblies -> components (multi-level)
# Each product gets 3-8 top-level assemblies
bom_edges = []  # (parent_id, child_id)  parent is Product or Part
product_top_assemblies = {}  # product_id -> [assembly_ids]

# Distribute assemblies across products
assembly_pool = list(assemblies)
random.shuffle(assembly_pool)
idx = 0
for pr in products:
    count = random.randint(3, 8)
    top_asms = []
    for _ in range(count):
        if idx >= len(assembly_pool):
            idx = 0
        asm = assembly_pool[idx % len(assembly_pool)]
        top_asms.append(asm["id"])
        bom_edges.append((pr["id"], asm["id"]))
        idx += 1
    product_top_assemblies[pr["id"]] = top_asms

# Each assembly gets 3-6 components (some assemblies can nest sub-assemblies for depth)
assembly_children = {}  # assembly_id -> [child_part_ids]
component_pool = list(components)
random.shuffle(component_pool)
cidx = 0

for asm in assemblies:
    num_children = random.randint(3, 6)
    children = []
    # With 30% chance, include a sub-assembly for depth
    if random.random() < 0.3 and len(assemblies) > 1:
        sub_asm = random.choice([a for a in assemblies if a["id"] != asm["id"]])
        children.append(sub_asm["id"])
        bom_edges.append((asm["id"], sub_asm["id"]))
        num_children -= 1
    for _ in range(num_children):
        comp = component_pool[cidx % len(component_pool)]
        children.append(comp["id"])
        bom_edges.append((asm["id"], comp["id"]))
        cidx += 1
    assembly_children[asm["id"]] = children

# Supply relationships: each COMPONENT supplied by 1-3 suppliers
supply_rels = []  # (supplier_id, part_id, priority, lead_time_days)
for comp in components:
    num_suppliers = random.randint(1, 3)
    chosen_suppliers = random.sample(suppliers, min(num_suppliers, len(suppliers)))
    for pri, sup in enumerate(chosen_suppliers, 1):
        ltd = random.randint(3, 30)
        supply_rels.append((sup["id"], comp["id"], pri, ltd))

# Also supply some assemblies
for asm in random.sample(assemblies, min(10, len(assemblies))):
    sup = random.choice(suppliers)
    supply_rels.append((sup["id"], asm["id"], 1, random.randint(5, 20)))

# Customers
customers = [
    {"id": "CUST1", "name": "空客集团 / Airbus Group"},
    {"id": "CUST2", "name": "一级OEM / Tier-1 OEM"},
    {"id": "CUST3", "name": "航天动力 / AeroPower Corp"},
    {"id": "CUST4", "name": "国防装备 / DefenseTech"},
    {"id": "CUST5", "name": "轨道交通 / RailSys"},
]

# Orders
orders = []
today = date(2026, 2, 15)
statuses_normal = ["Confirmed", "InProgress", "Shipped", "Planned"]
for i in range(1, NUM_ORDERS + 1):
    oid = f"SO{i:04d}"
    pr = random.choice(products)
    cust = random.choice(customers)
    od = rand_date(date(2026, 1, 1), date(2026, 3, 1))

    if oid in scenario_orders_at_risk:
        status = "AtRisk"
    elif oid in scenario_quality_hold_orders:
        status = "QualityHold"
    else:
        status = random.choice(statuses_normal)

    orders.append({
        "id": oid, "product": pr["id"], "customer": cust["id"],
        "order_date": od, "status": status,
    })

# Ensure scenario shortage parts are REQUIRES of their scenario orders
# Build order -> required parts
order_required_parts = {}
for o in orders:
    pr_id = o["product"]
    top_asms = product_top_assemblies.get(pr_id, [])
    # Collect leaf components reachable from product
    leaves = set()
    visited = set()
    stack = list(top_asms)
    while stack:
        nid = stack.pop()
        if nid in visited:
            continue
        visited.add(nid)
        children = assembly_children.get(nid, [])
        if not children or all(c.startswith("P") and int(c[1:]) > 40 for c in children if c.startswith("P")):
            # It's a leaf-ish node or component
            for c in children:
                leaves.add(c)
            if nid.startswith("P") and int(nid[1:]) > 40:
                leaves.add(nid)
        else:
            stack.extend(children)
    # Take a subset of leaves
    if leaves:
        subset_size = random.randint(2, min(8, len(leaves)))
        order_required_parts[o["id"]] = random.sample(sorted(leaves), subset_size)
    else:
        # Fallback: pick random components
        order_required_parts[o["id"]] = [random.choice(components)["id"] for _ in range(3)]

# Inject scenario shortage parts into scenario at-risk orders
for oid in scenario_orders_at_risk:
    for ps in scenario_parts_shortage:
        if oid in order_required_parts:
            if ps not in order_required_parts[oid]:
                order_required_parts[oid].append(ps)

# Purchase orders, shipments, inventory lots
purchase_orders = []
shipments_data = []
inventory_lots = []
po_counter = 2001
ship_counter = 3001
lot_counter = 4001

po_modes = ["Ocean", "Air", "Truck", "Rail"]
po_statuses = ["Open", "Closed", "QC_Hold"]
ship_statuses = ["InTransit", "Arrived", "Delayed", "Customs"]
inv_locations = ["F1-WH", "F2-WH", "F3-WH", "F1-LINE", "F2-LINE"]

for comp in components:
    # 1-2 POs per component
    num_pos = random.randint(1, 2)
    # Find a supplier for this component
    comp_suppliers = [sr for sr in supply_rels if sr[1] == comp["id"]]
    if not comp_suppliers:
        continue

    for _ in range(num_pos):
        sr = random.choice(comp_suppliers)
        po_id = f"PO-ERP-{po_counter}"
        po_counter += 1
        qty = random.randint(100, 5000)
        eta = rand_date(date(2026, 2, 10), date(2026, 4, 1))
        po_status = random.choice(po_statuses)

        purchase_orders.append({
            "id": po_id, "part_id": comp["id"], "supplier_id": sr[0],
            "qty": qty, "status": po_status, "eta": eta,
        })

        # Shipment for this PO
        ship_id = f"SHIP-{ship_counter}"
        ship_counter += 1
        mode = random.choice(po_modes)
        ship_status = random.choice(ship_statuses)
        ship_eta = eta + timedelta(days=random.randint(0, 5))
        shipments_data.append({
            "id": ship_id, "po_id": po_id, "mode": mode,
            "status": ship_status, "eta": ship_eta,
        })

    # Inventory lot
    lot_id = f"LOT-{lot_counter}"
    lot_counter += 1
    loc = random.choice(inv_locations)

    if comp["id"] in scenario_parts_shortage:
        ps = scenario_parts_shortage[comp["id"]]
        on_hand = ps.get("on_hand", 0)
        reserved = ps.get("reserved", 0)
    else:
        on_hand = random.randint(0, 2000)
        reserved = random.randint(0, min(on_hand, 500))

    inventory_lots.append({
        "id": lot_id, "part_id": comp["id"],
        "on_hand": on_hand, "reserved": reserved, "location": loc,
    })

# Production orders & work orders (MES)
prod_orders = []
work_orders = []
mo_counter = 5001
wo_counter = 6001
machines = []
machine_counter = 1
for f in factories:
    num_machines = random.randint(3, 6)
    for _ in range(num_machines):
        mid = f"M{machine_counter}"
        machine_counter += 1
        machines.append({
            "id": mid, "factory_id": f["id"],
            "status": random.choice(["Running", "Idle", "Maintenance"]),
            "capacity": random.randint(500, 2000),
        })

mo_statuses = ["Scheduled", "InProgress", "Completed", "Cancelled"]
for o in orders:
    mo_id = f"MO{mo_counter}"
    mo_counter += 1
    fac = random.choice(factories)
    ps = rand_date(date(2026, 2, 10), date(2026, 3, 15))
    pe = ps + timedelta(days=random.randint(3, 14))
    prod_orders.append({
        "id": mo_id, "sales_order_id": o["id"], "factory_id": fac["id"],
        "product_id": o["product"], "qty": random.randint(100, 3000),
        "status": random.choice(mo_statuses),
        "planned_start": ps, "planned_end": pe,
    })

    # 1-2 work orders per prod order
    for _ in range(random.randint(1, 2)):
        wo_id = f"WO{wo_counter}"
        wo_counter += 1
        m = random.choice([m for m in machines if m["factory_id"] == fac["id"]] or machines)
        work_orders.append({
            "id": wo_id, "prod_order_id": mo_id, "machine_id": m["id"],
            "status": random.choice(["NotReleased", "Released", "Active", "Done"]),
        })

# Cross-system status records
system_records = []
for o in orders:
    oid = o["id"]
    if oid in scenario_status_conflicts:
        conf = scenario_status_conflicts[oid]
        system_records.append({"order": oid, "system": "CRM", "status": conf["crm"]})
        system_records.append({"order": oid, "system": "SAP", "status": conf["sap"]})
        system_records.append({"order": oid, "system": "MES", "status": conf["mes"]})
    else:
        base_status = o["status"]
        # Most orders consistent, ~5% random inconsistency
        crm_status = base_status
        sap_status = base_status
        mes_status = base_status
        if random.random() < 0.05:
            sap_status = random.choice(["Open", "Cancelled", "Hold"])
        system_records.append({"order": oid, "system": "CRM", "status": crm_status})
        system_records.append({"order": oid, "system": "SAP", "status": sap_status})
        system_records.append({"order": oid, "system": "MES", "status": mes_status})


# ── ECO replacement part ────────────────────────────────────────────
eco_replacement_parts = []
for eco in scenario_ecos:
    rp_id = eco["replacement_part_id"]
    rp_name = eco["replacement_part_name"]
    eco_replacement_parts.append({"id": rp_id, "name": rp_name, "partType": "COMPONENT"})


# ══════════════════════════════════════════════════════════════════════
#  OUTPUT: SQL + CYPHER
# ══════════════════════════════════════════════════════════════════════

# ── CRM SQL ─────────────────────────────────────────────────────────
crm_lines = ["-- Generated by generate_demo_data.py\n"]

# Customers
crm_lines.append("INSERT INTO customers(customer_id, name) VALUES")
vals = []
for c in customers:
    vals.append(f"  ({sql_str(c['id'])}, {sql_str(c['name'])})")
crm_lines.append(",\n".join(vals))
crm_lines.append("ON CONFLICT DO NOTHING;\n")

# CRM orders
crm_lines.append("INSERT INTO crm_orders(crm_order_id, customer_id, order_date, status, updated_at) VALUES")
vals = []
for o in orders:
    vals.append(f"  ({sql_str(o['id'])}, {sql_str(o['customer'])}, {sql_date(o['order_date'])}, {sql_str(o['status'])}, now())")
crm_lines.append(",\n".join(vals))
crm_lines.append("ON CONFLICT DO NOTHING;\n")

crm_sql = "\n".join(crm_lines)

# ── ERP SQL ─────────────────────────────────────────────────────────
erp_lines = ["-- Generated by generate_demo_data.py\n"]

# Suppliers
erp_lines.append("INSERT INTO suppliers(supplier_id, name, approved) VALUES")
vals = []
for s in suppliers:
    vals.append(f"  ({sql_str(s['id'])}, {sql_str(s['name'])}, true)")
erp_lines.append(",\n".join(vals))
erp_lines.append("ON CONFLICT DO NOTHING;\n")

# Parts (all: products as PRODUCT type, assemblies, components, eco replacements)
erp_lines.append("INSERT INTO parts(part_id, name, part_type) VALUES")
vals = []
for pr in products:
    vals.append(f"  ({sql_str(pr['id'])}, {sql_str(pr['name'])}, 'PRODUCT')")
for p in all_parts:
    vals.append(f"  ({sql_str(p['id'])}, {sql_str(p['name'])}, {sql_str(p['partType'])})")
for rp in eco_replacement_parts:
    vals.append(f"  ({sql_str(rp['id'])}, {sql_str(rp['name'])}, {sql_str(rp['partType'])})")
erp_lines.append(",\n".join(vals))
erp_lines.append("ON CONFLICT DO NOTHING;\n")

# Supplier-parts
erp_lines.append("INSERT INTO supplier_parts(supplier_id, part_id, priority, lead_time_days) VALUES")
vals = []
for sr in supply_rels:
    vals.append(f"  ({sql_str(sr[0])}, {sql_str(sr[1])}, {sr[2]}, {sr[3]})")
erp_lines.append(",\n".join(vals))
erp_lines.append("ON CONFLICT DO NOTHING;\n")

# Purchase orders
erp_lines.append("INSERT INTO purchase_orders(po_id, part_id, supplier_id, qty, status, eta, updated_at) VALUES")
vals = []
for po in purchase_orders:
    vals.append(f"  ({sql_str(po['id'])}, {sql_str(po['part_id'])}, {sql_str(po['supplier_id'])}, {po['qty']}, {sql_str(po['status'])}, {sql_date(po['eta'])}, now())")
erp_lines.append(",\n".join(vals))
erp_lines.append("ON CONFLICT DO NOTHING;\n")

# Shipments
erp_lines.append("INSERT INTO shipments(shipment_id, po_id, mode, status, eta, updated_at) VALUES")
vals = []
for sh in shipments_data:
    vals.append(f"  ({sql_str(sh['id'])}, {sql_str(sh['po_id'])}, {sql_str(sh['mode'])}, {sql_str(sh['status'])}, {sql_date(sh['eta'])}, now())")
erp_lines.append(",\n".join(vals))
erp_lines.append("ON CONFLICT DO NOTHING;\n")

# Inventory lots
erp_lines.append("INSERT INTO inventory_lots(lot_id, part_id, on_hand, reserved, location, updated_at) VALUES")
vals = []
for inv in inventory_lots:
    vals.append(f"  ({sql_str(inv['id'])}, {sql_str(inv['part_id'])}, {inv['on_hand']}, {inv['reserved']}, {sql_str(inv['location'])}, now())")
erp_lines.append(",\n".join(vals))
erp_lines.append("ON CONFLICT DO NOTHING;\n")

erp_sql = "\n".join(erp_lines)

# ── MES SQL ─────────────────────────────────────────────────────────
mes_lines = ["-- Generated by generate_demo_data.py\n"]

# Factories
mes_lines.append("INSERT INTO factories(factory_id, name) VALUES")
vals = []
for f in factories:
    vals.append(f"  ({sql_str(f['id'])}, {sql_str(f['name'])})")
mes_lines.append(",\n".join(vals))
mes_lines.append("ON CONFLICT DO NOTHING;\n")

# Machines
mes_lines.append("INSERT INTO machines(machine_id, factory_id, status, capacity_per_day) VALUES")
vals = []
for m in machines:
    vals.append(f"  ({sql_str(m['id'])}, {sql_str(m['factory_id'])}, {sql_str(m['status'])}, {m['capacity']})")
mes_lines.append(",\n".join(vals))
mes_lines.append("ON CONFLICT DO NOTHING;\n")

# Production orders
mes_lines.append("INSERT INTO production_orders(prod_order_id, sales_order_id, factory_id, product_id, qty, status, planned_start, planned_end, updated_at) VALUES")
vals = []
for po in prod_orders:
    vals.append(f"  ({sql_str(po['id'])}, {sql_str(po['sales_order_id'])}, {sql_str(po['factory_id'])}, {sql_str(po['product_id'])}, {po['qty']}, {sql_str(po['status'])}, {sql_date(po['planned_start'])}, {sql_date(po['planned_end'])}, now())")
mes_lines.append(",\n".join(vals))
mes_lines.append("ON CONFLICT DO NOTHING;\n")

# Work orders
mes_lines.append("INSERT INTO work_orders(work_order_id, prod_order_id, machine_id, status, updated_at) VALUES")
vals = []
for wo in work_orders:
    vals.append(f"  ({sql_str(wo['id'])}, {sql_str(wo['prod_order_id'])}, {sql_str(wo['machine_id'])}, {sql_str(wo['status'])}, now())")
mes_lines.append(",\n".join(vals))
mes_lines.append("ON CONFLICT DO NOTHING;\n")

mes_sql = "\n".join(mes_lines)

# ── NEO4J CYPHER ────────────────────────────────────────────────────
cy = []
cy.append("// Generated by generate_demo_data.py")
cy.append("// Clean generated nodes")
cy.append("MATCH (n)")
cy.append("WHERE any(l IN labels(n) WHERE l IN ['Factory','Supplier','Part','Product','Order','SystemRecord','RiskEvent','Shipment','InventoryLot','DefectEvent','ECO'])")
cy.append("DETACH DELETE n;")
cy.append("")

# Factories
cy.append("// Factories")
for f in factories:
    cy.append(f"CREATE (:Factory {{id:{cypher_str(f['id'])}, name:{cypher_str(f['name'])}}});")
for fb in factory_backups:
    cy.append(f"MATCH (a:Factory {{id:{cypher_str(fb[0])}}}), (b:Factory {{id:{cypher_str(fb[1])}}}) CREATE (a)-[:CAN_BACKUP_WITH]->(b);")
cy.append("")

# Suppliers
cy.append("// Suppliers")
for s in suppliers:
    cy.append(f"CREATE (:Supplier {{id:{cypher_str(s['id'])}, name:{cypher_str(s['name'])}}});")

# Alternative supplier relationships
cy.append("MATCH (s2:Supplier {id:'S2'}), (s1:Supplier {id:'S1'}) CREATE (s2)-[:ALTERNATIVE_TO]->(s1);")
for alt in scenario_alternative_suppliers:
    if alt["from"] != "S2" or alt["to"] != "S1":  # Skip if already added
        cy.append(f"MATCH (a:Supplier {{id:{cypher_str(alt['from'])}}}), (b:Supplier {{id:{cypher_str(alt['to'])}}}) CREATE (a)-[:ALTERNATIVE_TO]->(b);")
cy.append("")

# Products
cy.append("// Products")
for pr in products:
    cy.append(f"CREATE (:Product {{id:{cypher_str(pr['id'])}, name:{cypher_str(pr['name'])}}});")
cy.append("")

# Parts
cy.append("// Parts")
for p in all_parts:
    cy.append(f"CREATE (:Part {{id:{cypher_str(p['id'])}, name:{cypher_str(p['name'])}, partType:{cypher_str(p['partType'])}}});")
# ECO replacement parts
for rp in eco_replacement_parts:
    cy.append(f"CREATE (:Part {{id:{cypher_str(rp['id'])}, name:{cypher_str(rp['name'])}, partType:{cypher_str(rp['partType'])}}});")
cy.append("")

# BOM edges (batched for performance)
cy.append("// BOM relationships")
# Product -> Part
product_bom = [(p, c) for p, c in bom_edges if p.startswith("PR")]
part_bom = [(p, c) for p, c in bom_edges if not p.startswith("PR")]

for parent, child in product_bom:
    cy.append(f"MATCH (a:Product {{id:{cypher_str(parent)}}}), (b:Part {{id:{cypher_str(child)}}}) CREATE (a)-[:HAS_COMPONENT]->(b);")
for parent, child in part_bom:
    cy.append(f"MATCH (a:Part {{id:{cypher_str(parent)}}}), (b:Part {{id:{cypher_str(child)}}}) CREATE (a)-[:HAS_COMPONENT]->(b);")
cy.append("")

# Factory produces
cy.append("// Factory produces")
# Distribute products across factories
for i, pr in enumerate(products):
    fid = factories[i % NUM_FACTORIES]["id"]
    cy.append(f"MATCH (f:Factory {{id:{cypher_str(fid)}}}), (p:Product {{id:{cypher_str(pr['id'])}}}) CREATE (f)-[:PRODUCES]->(p);")
cy.append("")

# Supply relationships
cy.append("// Supply relationships")
for sr in supply_rels:
    cy.append(f"MATCH (s:Supplier {{id:{cypher_str(sr[0])}}}), (p:Part {{id:{cypher_str(sr[1])}}}) CREATE (s)-[:SUPPLIES {{priority:{sr[2]}, leadTimeDays:{sr[3]}}}]->(p);")
cy.append("")

# Orders
cy.append("// Orders")
for o in orders:
    cy.append(f"CREATE (:Order {{id:{cypher_str(o['id'])}, status:{cypher_str(o['status'])}}});")
cy.append("")

# Order -> Product (PRODUCES)
cy.append("// Order -> Product")
for o in orders:
    cy.append(f"MATCH (o:Order {{id:{cypher_str(o['id'])}}}), (p:Product {{id:{cypher_str(o['product'])}}}) CREATE (o)-[:PRODUCES]->(p);")
cy.append("")

# Order -> Part (REQUIRES)
cy.append("// Order -> Required Parts")
for oid, parts in order_required_parts.items():
    for pid in parts:
        cy.append(f"MATCH (o:Order {{id:{cypher_str(oid)}}}), (p:Part {{id:{cypher_str(pid)}}}) CREATE (o)-[:REQUIRES]->(p);")
cy.append("")

# System records
cy.append("// System records")
for sr in system_records:
    cy.append(f"CREATE (s:SystemRecord {{system:{cypher_str(sr['system'])}, objectType:'Order', objectId:{cypher_str(sr['order'])}, status:{cypher_str(sr['status'])}, updatedAt:datetime()}});")
    cy.append(f"MATCH (o:Order {{id:{cypher_str(sr['order'])}}}), (s:SystemRecord {{system:{cypher_str(sr['system'])}, objectId:{cypher_str(sr['order'])}}}) CREATE (o)-[:HAS_STATUS]->(s);")
cy.append("")

# Risk events
cy.append("// Risk events")
# Existing R1 from seed.cypher is cleaned, so re-add scenario risk events
for re in scenario_risk_events:
    d = re.get("date", "2026-02-10")
    cy.append(f"CREATE (:RiskEvent {{id:{cypher_str(re['id'])}, type:{cypher_str(re['type'])}, severity:{re['severity']}, date:date('{d}')}});")
    cy.append(f"MATCH (r:RiskEvent {{id:{cypher_str(re['id'])}}}), (s:Supplier {{id:{cypher_str(re['supplier'])}}}) CREATE (r)-[:AFFECTS]->(s);")
cy.append("")

# Shipments
cy.append("// Shipments")
for sh in shipments_data:
    cy.append(f"CREATE (:Shipment {{id:{cypher_str(sh['id'])}, mode:{cypher_str(sh['mode'])}, status:{cypher_str(sh['status'])}, eta:date('{sh['eta']}')}});")
for sh in shipments_data:
    # Find PO to get part
    po_match = [po for po in purchase_orders if po["id"] == sh["po_id"]]
    if po_match:
        pid = po_match[0]["part_id"]
        cy.append(f"MATCH (s:Shipment {{id:{cypher_str(sh['id'])}}}), (p:Part {{id:{cypher_str(pid)}}}) CREATE (s)-[:DELIVERS]->(p);")
cy.append("")

# Inventory lots
cy.append("// Inventory lots")
for inv in inventory_lots:
    cy.append(f"CREATE (:InventoryLot {{id:{cypher_str(inv['id'])}, location:{cypher_str(inv['location'])}, onHand:{inv['on_hand']}, reserved:{inv['reserved']}}});")
    cy.append(f"MATCH (i:InventoryLot {{id:{cypher_str(inv['id'])}}}), (p:Part {{id:{cypher_str(inv['part_id'])}}}) CREATE (i)-[:STORES]->(p);")
cy.append("")

# Defect events
cy.append("// Defect events")
for d in scenario_defects:
    dt = d.get("date", "2026-02-13")
    cy.append(f"CREATE (:DefectEvent {{id:{cypher_str(d['id'])}, description:{cypher_str(d['description'])}, severity:{d['severity']}, date:date('{dt}')}});")
    cy.append(f"MATCH (p:Part {{id:{cypher_str(d['part'])}}}), (d:DefectEvent {{id:{cypher_str(d['id'])}}}) CREATE (p)-[:HAS_DEFECT]->(d);")
cy.append("")

# ECO
cy.append("// Engineering Change Orders")
for e in scenario_ecos:
    dt = e.get("date", "2026-02-14")
    cy.append(f"CREATE (:ECO {{id:{cypher_str(e['id'])}, description:{cypher_str(e['description'])}, status:{cypher_str(e['status'])}, date:date('{dt}')}});")
    cy.append(f"MATCH (e:ECO {{id:{cypher_str(e['id'])}}}), (p:Part {{id:{cypher_str(e['affected_part'])}}}) CREATE (e)-[:ECO_AFFECTS]->(p);")
    cy.append(f"MATCH (e:ECO {{id:{cypher_str(e['id'])}}}), (p:Part {{id:{cypher_str(e['replacement_part_id'])}}}) CREATE (e)-[:ECO_REPLACES_WITH]->(p);")
cy.append("")

cypher_content = "\n".join(cy)

# ── Write output files ──────────────────────────────────────────────
out_crm = ROOT / "infra" / "postgres" / "crm" / "03_seed_generated.sql"
out_erp = ROOT / "infra" / "postgres" / "erp" / "03_seed_generated.sql"
out_mes = ROOT / "infra" / "postgres" / "mes" / "03_seed_generated.sql"
out_neo4j = ROOT / "infra" / "neo4j" / "seed_generated.cypher"

out_crm.write_text(crm_sql, encoding="utf-8")
out_erp.write_text(erp_sql, encoding="utf-8")
out_mes.write_text(mes_sql, encoding="utf-8")
out_neo4j.write_text(cypher_content, encoding="utf-8")

print(f"Generated {out_crm}  ({len(crm_sql):,} bytes)")
print(f"Generated {out_erp}  ({len(erp_sql):,} bytes)")
print(f"Generated {out_mes}  ({len(mes_sql):,} bytes)")
print(f"Generated {out_neo4j} ({len(cypher_content):,} bytes)")
print(f"\nStats: {NUM_FACTORIES} factories, {NUM_SUPPLIERS} suppliers, "
      f"{len(products)} products, {len(all_parts)} parts, "
      f"{len(orders)} orders, {len(bom_edges)} BOM edges, "
      f"{len(supply_rels)} supply rels, {len(purchase_orders)} POs, "
      f"{len(shipments_data)} shipments, {len(inventory_lots)} inventory lots, "
      f"{len(scenario_risk_events)} risk events, {len(scenario_defects)} defects, "
      f"{len(scenario_ecos)} ECOs")
