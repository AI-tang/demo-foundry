"""Twin-Sim  –  Rule-based What-if simulation for supply chain (MVP)."""

from __future__ import annotations

import os
from typing import Optional

from fastapi import FastAPI, HTTPException
from neo4j import GraphDatabase
from pydantic import BaseModel, Field

# ────────────────────────────────────────────────────────────────────
# App & Neo4j
# ────────────────────────────────────────────────────────────────────

app = FastAPI(title="Twin-Sim", version="0.1.0")

NEO4J_URI = os.getenv("NEO4J_URI", "bolt://neo4j:7687")
NEO4J_USER = os.getenv("NEO4J_USER", "neo4j")
NEO4J_PASSWORD = os.getenv("NEO4J_PASSWORD", "demo12345")

_driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))


@app.on_event("shutdown")
def _close_driver() -> None:
    _driver.close()


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}


# ────────────────────────────────────────────────────────────────────
# Pydantic models
# ────────────────────────────────────────────────────────────────────

class Scenario(BaseModel):
    label: str
    description: str
    eta_delta_days: int
    cost_delta_pct: float
    line_stop_risk: float
    quality_risk: float
    assumptions: list[str]


class BlastRadiusItem(BaseModel):
    id: str
    name: str
    type: str


class BlastRadiusPath(BaseModel):
    from_node: str = Field(serialization_alias="from")
    relation: str
    to_node: str = Field(serialization_alias="to")


class BlastRadius(BaseModel):
    impactedOrders: list[BlastRadiusItem]
    impactedParts: list[BlastRadiusItem]
    impactedFactories: list[BlastRadiusItem]
    paths: list[BlastRadiusPath]


class SimulationResult(BaseModel):
    scenarios: list[Scenario]
    recommended: str
    blastRadius: BlastRadius
    assumptions: list[str]


# ── Request bodies ──

class SwitchSupplierReq(BaseModel):
    orderId: str
    partId: str
    fromSupplierId: Optional[str] = None
    toSupplierId: str
    objective: str = "delivery-first"
    constraints: dict = {}


class ChangeLaneReq(BaseModel):
    orderId: str
    partId: str
    supplierId: str
    toLane: str  # "Ocean" | "Air"
    objective: str = "delivery-first"
    constraints: dict = {}


class TransferFactoryReq(BaseModel):
    orderId: str
    fromFactoryId: Optional[str] = None
    toFactoryId: str
    objective: str = "delivery-first"
    constraints: dict = {}


# ────────────────────────────────────────────────────────────────────
# Neo4j helpers
# ────────────────────────────────────────────────────────────────────

def _val(v):
    """Unwrap neo4j int/float wrappers."""
    if v is None:
        return None
    if hasattr(v, "__int__"):
        return int(v)
    if hasattr(v, "__float__"):
        return float(v)
    return v


def _get_supplier_part(tx, supplier_id: str, part_id: str) -> dict | None:
    r = tx.run(
        """
        MATCH (s:Supplier {id: $sid})-[r:SUPPLIES]->(p:Part {id: $pid})
        RETURN s.id AS supplierId, s.name AS supplierName,
               r.leadTimeDays AS leadTimeDays, r.moq AS moq,
               r.capacity AS capacity, r.lastPrice AS lastPrice,
               r.qualificationLevel AS qualificationLevel
        """,
        sid=supplier_id, pid=part_id,
    )
    rec = r.single()
    return {k: _val(rec[k]) for k in rec.keys()} if rec else None


def _get_lanes(tx, supplier_id: str, factory_id: str) -> list[dict]:
    r = tx.run(
        """
        MATCH (tl:TransportLane)
        WHERE tl.fromNode = $sid AND tl.toNode = $fid
        RETURN tl.mode AS mode, tl.timeDays AS timeDays,
               tl.cost AS cost, tl.reliability AS reliability
        ORDER BY tl.timeDays
        """,
        sid=supplier_id, fid=factory_id,
    )
    return [{k: _val(rec[k]) for k in rec.keys()} for rec in r]


def _get_inventory(tx, part_id: str, factory_prefix: str) -> dict | None:
    r = tx.run(
        """
        MATCH (inv:InventoryLot)-[:STORES]->(p:Part {id: $pid})
        WHERE inv.location STARTS WITH $fpfx
        RETURN sum(inv.onHand) AS onHand,
               sum(inv.reserved) AS reserved,
               max(inv.safetyStock) AS safetyStock
        """,
        pid=part_id, fpfx=factory_prefix,
    )
    rec = r.single()
    if rec and rec["onHand"] is not None:
        return {k: _val(rec[k]) for k in rec.keys()}
    return None


def _get_risk_events(tx, supplier_id: str) -> list[dict]:
    r = tx.run(
        """
        MATCH (re:RiskEvent)-[:AFFECTS]->(s:Supplier {id: $sid})
        RETURN re.id AS id, re.type AS type, re.severity AS severity
        """,
        sid=supplier_id,
    )
    return [{k: _val(rec[k]) for k in rec.keys()} for rec in r]


def _get_quality_hold(tx, supplier_id: str, part_id: str) -> dict | None:
    r = tx.run(
        """
        MATCH (qh:QualityHold)
        WHERE qh.supplierId = $sid AND qh.partId = $pid
        RETURN qh.holdDays AS holdDays, qh.reason AS reason
        """,
        sid=supplier_id, pid=part_id,
    )
    rec = r.single()
    return {k: _val(rec[k]) for k in rec.keys()} if rec else None


def _get_order_factory(tx, order_id: str) -> dict | None:
    r = tx.run(
        """
        MATCH (o:Order {id: $oid})-[:PRODUCES]->(pr:Product)<-[:PRODUCES]-(f:Factory)
        RETURN f.id AS factoryId, f.name AS factoryName
        LIMIT 1
        """,
        oid=order_id,
    )
    rec = r.single()
    return {k: _val(rec[k]) for k in rec.keys()} if rec else None


def _get_current_supplier(tx, order_id: str, part_id: str) -> str | None:
    r = tx.run(
        """
        MATCH (o:Order {id: $oid})-[:REQUIRES]->(p:Part {id: $pid})<-[r:SUPPLIES]-(s:Supplier)
        RETURN s.id AS sid ORDER BY r.priority LIMIT 1
        """,
        oid=order_id, pid=part_id,
    )
    rec = r.single()
    return str(rec["sid"]) if rec else None


def _blast_radius(tx, order_id: str | None, supplier_id: str | None, part_id: str | None) -> BlastRadius:
    orders, parts, factories, paths = [], [], [], []

    if order_id:
        r = tx.run(
            """
            MATCH (o:Order {id: $id})-[:REQUIRES]->(p:Part)
            OPTIONAL MATCH (p)<-[:SUPPLIES]-(s:Supplier)
            OPTIONAL MATCH (p)<-[:REQUIRES]-(other:Order) WHERE other.id <> $id
            OPTIONAL MATCH (o)-[:PRODUCES]->(pr:Product)<-[:PRODUCES]-(f:Factory)
            RETURN collect(DISTINCT other {.id, .status}) AS otherOrders,
                   collect(DISTINCT p {.id, .name})        AS parts,
                   collect(DISTINCT f {.id, .name})        AS factories,
                   collect(DISTINCT [o.id, 'REQUIRES', p.id]) +
                   collect(DISTINCT [s.id, 'SUPPLIES', p.id]) AS rawPaths
            """,
            id=order_id,
        )
    elif supplier_id:
        r = tx.run(
            """
            MATCH (s:Supplier {id: $id})-[:SUPPLIES]->(p:Part)<-[:REQUIRES]-(o:Order)
            OPTIONAL MATCH (o)-[:PRODUCES]->(pr:Product)<-[:PRODUCES]-(f:Factory)
            RETURN collect(DISTINCT o {.id, .status}) AS otherOrders,
                   collect(DISTINCT p {.id, .name})   AS parts,
                   collect(DISTINCT f {.id, .name})   AS factories,
                   collect(DISTINCT [s.id, 'SUPPLIES', p.id]) +
                   collect(DISTINCT [o.id, 'REQUIRES', p.id]) AS rawPaths
            """,
            id=supplier_id,
        )
    elif part_id:
        r = tx.run(
            """
            MATCH (p:Part {id: $id})<-[:REQUIRES]-(o:Order)
            OPTIONAL MATCH (p)<-[:SUPPLIES]-(s:Supplier)
            OPTIONAL MATCH (o)-[:PRODUCES]->(pr:Product)<-[:PRODUCES]-(f:Factory)
            RETURN collect(DISTINCT o {.id, .status}) AS otherOrders,
                   collect(DISTINCT p {.id, .name})   AS parts,
                   collect(DISTINCT f {.id, .name})   AS factories,
                   collect(DISTINCT [o.id, 'REQUIRES', p.id]) +
                   collect(DISTINCT [s.id, 'SUPPLIES', p.id]) AS rawPaths
            """,
            id=part_id,
        )
    else:
        return BlastRadius(impactedOrders=[], impactedParts=[], impactedFactories=[], paths=[])

    rec = r.single()
    if rec:
        for o in rec["otherOrders"]:
            if o and o.get("id"):
                orders.append(BlastRadiusItem(id=o["id"], name=o["id"], type="Order"))
        for p in rec["parts"]:
            if p and p.get("id"):
                parts.append(BlastRadiusItem(id=p["id"], name=p.get("name", p["id"]), type="Part"))
        for f in rec["factories"]:
            if f and f.get("id"):
                factories.append(BlastRadiusItem(id=f["id"], name=f.get("name", f["id"]), type="Factory"))
        for rp in rec["rawPaths"]:
            if rp and len(rp) == 3 and rp[0] and rp[2]:
                paths.append(BlastRadiusPath(from_node=str(rp[0]), relation=str(rp[1]), to_node=str(rp[2])))

    return BlastRadius(impactedOrders=orders, impactedParts=parts, impactedFactories=factories, paths=paths)


# ────────────────────────────────────────────────────────────────────
# Rules engine
# ────────────────────────────────────────────────────────────────────

QUAL_RISK_MAP = {"Full": 0.05, "Conditional": 0.25, "Pending": 0.50}
DEFAULT_DAILY_CONSUMPTION = 10  # units/day estimate


def _line_stop_risk(coverage_days: float, eta_days: int, reliability: float, risk_severity: int) -> float:
    eta_days = max(eta_days, 1)
    ratio = coverage_days / eta_days
    if ratio >= 2.0:
        base = 0.05
    elif ratio >= 1.0:
        base = 0.15
    elif ratio >= 0.5:
        base = 0.45
    else:
        base = 0.80
    lane_pen = (1.0 - reliability) * 0.3
    risk_pen = min(risk_severity / 10.0, 0.5) if risk_severity else 0.0
    return round(min(base + lane_pen + risk_pen, 1.0), 2)


def _pick_lane(lanes: list[dict], mode: str) -> dict:
    for ln in lanes:
        if ln["mode"] == mode:
            return ln
    return lanes[0] if lanes else {"mode": mode, "timeDays": 14, "cost": 1.0, "reliability": 0.85}


def _default_lane(mode: str) -> dict:
    if mode == "Air":
        return {"mode": "Air", "timeDays": 3, "cost": 5.0, "reliability": 0.97}
    return {"mode": "Ocean", "timeDays": 14, "cost": 0.60, "reliability": 0.88}


# ────────────────────────────────────────────────────────────────────
# POST /simulate/switch-supplier
# ────────────────────────────────────────────────────────────────────

@app.post("/simulate/switch-supplier", response_model=SimulationResult)
def switch_supplier(req: SwitchSupplierReq) -> SimulationResult:
    with _driver.session() as s:
        factory = s.execute_read(_get_order_factory, req.orderId)
        fid = factory["factoryId"] if factory else "F1"

        from_sid = req.fromSupplierId or s.execute_read(_get_current_supplier, req.orderId, req.partId)
        if not from_sid:
            raise HTTPException(404, f"No current supplier found for {req.partId} on {req.orderId}")

        from_data = s.execute_read(_get_supplier_part, from_sid, req.partId)
        to_data = s.execute_read(_get_supplier_part, req.toSupplierId, req.partId)
        from_lanes = s.execute_read(_get_lanes, from_sid, fid)
        to_lanes = s.execute_read(_get_lanes, req.toSupplierId, fid)
        inv = s.execute_read(_get_inventory, req.partId, fid)
        from_risks = s.execute_read(_get_risk_events, from_sid)
        to_risks = s.execute_read(_get_risk_events, req.toSupplierId)
        qc_hold = s.execute_read(_get_quality_hold, req.toSupplierId, req.partId)
        blast = s.execute_read(_blast_radius, req.orderId, None, None)

    # Inventory coverage
    avail = ((inv["onHand"] or 0) - (inv["reserved"] or 0)) if inv else 0
    safety = (inv["safetyStock"] or 0) if inv else 0
    net = max(avail - safety, 0)
    cov_days = net / DEFAULT_DAILY_CONSUMPTION

    # Lanes
    from_ocean = _pick_lane(from_lanes, "Ocean") if from_lanes else _default_lane("Ocean")
    to_ocean = _pick_lane(to_lanes, "Ocean") if to_lanes else _default_lane("Ocean")
    to_air = _pick_lane(to_lanes, "Air") if to_lanes else _default_lane("Air")

    # QC hold days
    to_qual = (to_data or {}).get("qualificationLevel", "Pending")
    qc_days = (qc_hold or {}).get("holdDays", 0)
    if to_qual != "Full" and qc_days == 0:
        qc_days = 5

    from_risk_sev = max((r.get("severity", 0) for r in from_risks), default=0)
    to_risk_sev = max((r.get("severity", 0) for r in to_risks), default=0)

    from_lead = (from_data or {}).get("leadTimeDays", 14)
    from_price = (from_data or {}).get("lastPrice", 10.0)
    from_qual = (from_data or {}).get("qualificationLevel", "Full")
    to_lead = (to_data or {}).get("leadTimeDays", 10)
    to_price = (to_data or {}).get("lastPrice", 14.0)
    from_name = (from_data or {}).get("supplierName", from_sid)
    to_name = (to_data or {}).get("supplierName", req.toSupplierId)

    # Scenario A – keep current
    a_eta = from_lead + from_ocean["timeDays"]
    a_cost = from_price + from_ocean["cost"]
    a_ls = _line_stop_risk(cov_days, a_eta, from_ocean["reliability"], from_risk_sev)
    a_qr = QUAL_RISK_MAP.get(from_qual, 0.05)

    # Scenario B – switch, ocean
    b_eta = to_lead + to_ocean["timeDays"] + qc_days
    b_cost = to_price + to_ocean["cost"]
    b_ls = _line_stop_risk(cov_days, b_eta, to_ocean["reliability"], to_risk_sev)
    b_qr = QUAL_RISK_MAP.get(to_qual, 0.25)

    # Scenario C – switch, air expedite
    c_eta = to_lead + to_air["timeDays"] + qc_days
    c_cost = to_price + to_air["cost"]
    c_ls = _line_stop_risk(cov_days, c_eta, to_air["reliability"], to_risk_sev)
    c_qr = QUAL_RISK_MAP.get(to_qual, 0.25)

    base_eta, base_cost = a_eta, a_cost

    def _delta_pct(cost: float) -> float:
        return round((cost - base_cost) / base_cost * 100, 1) if base_cost else 0

    scenarios = [
        Scenario(
            label="A",
            description=f"Keep {from_name} (Ocean)",
            eta_delta_days=0,
            cost_delta_pct=0,
            line_stop_risk=a_ls,
            quality_risk=a_qr,
            assumptions=[
                f"Lead {from_lead}d + Ocean {from_ocean['timeDays']}d = {a_eta}d",
                f"Unit ${from_price:.2f} + ship ${from_ocean['cost']:.2f}",
                f"Qualification: {from_qual}",
            ],
        ),
        Scenario(
            label="B",
            description=f"Switch to {to_name} (Ocean)",
            eta_delta_days=b_eta - base_eta,
            cost_delta_pct=_delta_pct(b_cost),
            line_stop_risk=b_ls,
            quality_risk=b_qr,
            assumptions=[
                f"Lead {to_lead}d + Ocean {to_ocean['timeDays']}d + QC {qc_days}d = {b_eta}d",
                f"Unit ${to_price:.2f} + ship ${to_ocean['cost']:.2f}",
                f"Qualification: {to_qual}" + (" -> re-certification required" if to_qual != "Full" else ""),
            ],
        ),
        Scenario(
            label="C",
            description=f"Switch to {to_name} (Air expedite)",
            eta_delta_days=c_eta - base_eta,
            cost_delta_pct=_delta_pct(c_cost),
            line_stop_risk=c_ls,
            quality_risk=c_qr,
            assumptions=[
                f"Lead {to_lead}d + Air {to_air['timeDays']}d + QC {qc_days}d = {c_eta}d",
                f"Unit ${to_price:.2f} + ship ${to_air['cost']:.2f} (expedite)",
                f"Qualification: {to_qual}" + (" -> re-certification required" if to_qual != "Full" else ""),
            ],
        ),
    ]

    # Recommend (delivery-first by default)
    scored = [(sc, sc.eta_delta_days + sc.line_stop_risk * 20 + sc.quality_risk * 10) for sc in scenarios]
    if req.objective == "cost-first":
        scored = [(sc, sc.cost_delta_pct + sc.line_stop_risk * 20) for sc in scenarios]
    recommended = min(scored, key=lambda x: x[1])[0].label

    assumptions = [
        f"Inventory: {avail} on-hand, {safety} safety stock, ~{cov_days:.0f}d coverage",
        f"Daily consumption: ~{DEFAULT_DAILY_CONSUMPTION} units/day (est.)",
    ]
    if from_risk_sev > 0:
        assumptions.append(f"Current supplier has active risk (max severity {from_risk_sev})")
    if to_qual != "Full":
        assumptions.append(f"Target supplier qualification={to_qual}, QC hold={qc_days}d")

    return SimulationResult(
        scenarios=scenarios, recommended=recommended,
        blastRadius=blast, assumptions=assumptions,
    )


# ────────────────────────────────────────────────────────────────────
# POST /simulate/change-lane
# ────────────────────────────────────────────────────────────────────

@app.post("/simulate/change-lane", response_model=SimulationResult)
def change_lane(req: ChangeLaneReq) -> SimulationResult:
    with _driver.session() as s:
        factory = s.execute_read(_get_order_factory, req.orderId)
        fid = factory["factoryId"] if factory else "F1"
        sp_data = s.execute_read(_get_supplier_part, req.supplierId, req.partId)
        lanes = s.execute_read(_get_lanes, req.supplierId, fid)
        inv = s.execute_read(_get_inventory, req.partId, fid)
        risks = s.execute_read(_get_risk_events, req.supplierId)
        blast = s.execute_read(_blast_radius, req.orderId, None, None)

    lead = (sp_data or {}).get("leadTimeDays", 14)
    price = (sp_data or {}).get("lastPrice", 10.0)
    qual = (sp_data or {}).get("qualificationLevel", "Full")
    sname = (sp_data or {}).get("supplierName", req.supplierId)
    risk_sev = max((r.get("severity", 0) for r in risks), default=0)
    q_risk = QUAL_RISK_MAP.get(qual, 0.05)

    avail = ((inv["onHand"] or 0) - (inv["reserved"] or 0)) if inv else 0
    safety = (inv["safetyStock"] or 0) if inv else 0
    cov_days = max(avail - safety, 0) / DEFAULT_DAILY_CONSUMPTION

    ocean = _pick_lane(lanes, "Ocean") if lanes else _default_lane("Ocean")
    air = _pick_lane(lanes, "Air") if lanes else _default_lane("Air")

    a_eta = lead + ocean["timeDays"]
    a_cost = price + ocean["cost"]
    b_eta = lead + air["timeDays"]
    b_cost = price + air["cost"]
    # Scenario C: partial air (50% ocean cost + 50% air cost, 60% ocean time + 40% air time)
    c_eta = lead + int(ocean["timeDays"] * 0.6 + air["timeDays"] * 0.4)
    c_cost = price + ocean["cost"] * 0.5 + air["cost"] * 0.5

    base_eta, base_cost = a_eta, a_cost

    def _dp(c: float) -> float:
        return round((c - base_cost) / base_cost * 100, 1) if base_cost else 0

    scenarios = [
        Scenario(label="A", description=f"{sname} Ocean (current)",
                 eta_delta_days=0, cost_delta_pct=0,
                 line_stop_risk=_line_stop_risk(cov_days, a_eta, ocean["reliability"], risk_sev),
                 quality_risk=q_risk,
                 assumptions=[f"Lead {lead}d + Ocean {ocean['timeDays']}d = {a_eta}d",
                              f"${price:.2f} + ship ${ocean['cost']:.2f}"]),
        Scenario(label="B", description=f"{sname} Air",
                 eta_delta_days=b_eta - base_eta, cost_delta_pct=_dp(b_cost),
                 line_stop_risk=_line_stop_risk(cov_days, b_eta, air["reliability"], risk_sev),
                 quality_risk=q_risk,
                 assumptions=[f"Lead {lead}d + Air {air['timeDays']}d = {b_eta}d",
                              f"${price:.2f} + ship ${air['cost']:.2f} (expedite)"]),
        Scenario(label="C", description=f"{sname} Multi-modal (Ocean+Air)",
                 eta_delta_days=c_eta - base_eta, cost_delta_pct=_dp(c_cost),
                 line_stop_risk=_line_stop_risk(cov_days, c_eta, (ocean["reliability"] + air["reliability"]) / 2, risk_sev),
                 quality_risk=q_risk,
                 assumptions=[f"Lead {lead}d + blended {c_eta - lead}d = {c_eta}d",
                              f"${price:.2f} + blended ship ${ocean['cost'] * 0.5 + air['cost'] * 0.5:.2f}"]),
    ]

    scored = [(sc, sc.eta_delta_days + sc.line_stop_risk * 20) for sc in scenarios]
    if req.objective == "cost-first":
        scored = [(sc, sc.cost_delta_pct + sc.line_stop_risk * 20) for sc in scenarios]
    recommended = min(scored, key=lambda x: x[1])[0].label

    return SimulationResult(
        scenarios=scenarios, recommended=recommended, blastRadius=blast,
        assumptions=[f"Inventory: ~{cov_days:.0f}d coverage", f"Supplier: {sname}, qual={qual}"],
    )


# ────────────────────────────────────────────────────────────────────
# POST /simulate/transfer-factory
# ────────────────────────────────────────────────────────────────────

@app.post("/simulate/transfer-factory", response_model=SimulationResult)
def transfer_factory(req: TransferFactoryReq) -> SimulationResult:
    with _driver.session() as s:
        # Current factory
        cur_factory = s.execute_read(_get_order_factory, req.orderId)
        from_fid = req.fromFactoryId or (cur_factory["factoryId"] if cur_factory else "F1")

        # Parts required by order
        r = s.execute_read(
            lambda tx: tx.run(
                "MATCH (o:Order {id:$oid})-[:REQUIRES]->(p:Part)<-[r:SUPPLIES]-(s:Supplier) "
                "RETURN p.id AS pid, s.id AS sid, r.leadTimeDays AS lead, r.lastPrice AS price, "
                "r.qualificationLevel AS qual ORDER BY r.priority LIMIT 1",
                oid=req.orderId,
            ).single(),
        )
        pid = r["pid"] if r else "P1A"
        sid = r["sid"] if r else "S1"
        lead = _val(r["lead"]) if r else 14
        price = _val(r["price"]) if r else 10.0
        qual = r["qual"] if r else "Full"

        from_lanes = s.execute_read(_get_lanes, sid, from_fid)
        to_lanes = s.execute_read(_get_lanes, sid, req.toFactoryId)
        from_inv = s.execute_read(_get_inventory, pid, from_fid)
        to_inv = s.execute_read(_get_inventory, pid, req.toFactoryId)
        risks = s.execute_read(_get_risk_events, sid)
        blast = s.execute_read(_blast_radius, req.orderId, None, None)

    risk_sev = max((rv.get("severity", 0) for rv in risks), default=0)
    q_risk = QUAL_RISK_MAP.get(qual, 0.05)

    # From factory
    f_ocean = _pick_lane(from_lanes, "Ocean") if from_lanes else _default_lane("Ocean")
    f_avail = ((from_inv["onHand"] or 0) - (from_inv["reserved"] or 0)) if from_inv else 0
    f_safety = (from_inv["safetyStock"] or 0) if from_inv else 0
    f_cov = max(f_avail - f_safety, 0) / DEFAULT_DAILY_CONSUMPTION

    # To factory
    t_ocean = _pick_lane(to_lanes, "Ocean") if to_lanes else _default_lane("Ocean")
    t_air = _pick_lane(to_lanes, "Air") if to_lanes else _default_lane("Air")
    t_avail = ((to_inv["onHand"] or 0) - (to_inv["reserved"] or 0)) if to_inv else 0
    t_safety = (to_inv["safetyStock"] or 0) if to_inv else 0
    t_cov = max(t_avail - t_safety, 0) / DEFAULT_DAILY_CONSUMPTION

    ramp_up_days = 5  # factory transfer ramp-up

    a_eta = lead + f_ocean["timeDays"]
    b_eta = lead + t_ocean["timeDays"] + ramp_up_days
    c_eta = lead + t_air["timeDays"] + ramp_up_days

    a_cost = price + f_ocean["cost"]
    b_cost = price + t_ocean["cost"] + 1.0  # transfer overhead
    c_cost = price + t_air["cost"] + 1.0

    base_eta, base_cost = a_eta, a_cost

    def _dp(c: float) -> float:
        return round((c - base_cost) / base_cost * 100, 1) if base_cost else 0

    scenarios = [
        Scenario(label="A", description=f"Keep at {from_fid} (current)",
                 eta_delta_days=0, cost_delta_pct=0,
                 line_stop_risk=_line_stop_risk(f_cov, a_eta, f_ocean["reliability"], risk_sev),
                 quality_risk=q_risk,
                 assumptions=[f"Lead {lead}d + Ocean {f_ocean['timeDays']}d = {a_eta}d at {from_fid}",
                              f"Inv: {f_avail} units at {from_fid}"]),
        Scenario(label="B", description=f"Transfer to {req.toFactoryId} (Ocean)",
                 eta_delta_days=b_eta - base_eta, cost_delta_pct=_dp(b_cost),
                 line_stop_risk=_line_stop_risk(t_cov, b_eta, t_ocean["reliability"], risk_sev),
                 quality_risk=q_risk + 0.05,
                 assumptions=[f"Lead {lead}d + Ocean {t_ocean['timeDays']}d + ramp-up {ramp_up_days}d = {b_eta}d",
                              f"Inv: {t_avail} units at {req.toFactoryId}",
                              f"+$1.00 transfer overhead"]),
        Scenario(label="C", description=f"Transfer to {req.toFactoryId} (Air expedite)",
                 eta_delta_days=c_eta - base_eta, cost_delta_pct=_dp(c_cost),
                 line_stop_risk=_line_stop_risk(t_cov, c_eta, t_air["reliability"], risk_sev),
                 quality_risk=q_risk + 0.05,
                 assumptions=[f"Lead {lead}d + Air {t_air['timeDays']}d + ramp-up {ramp_up_days}d = {c_eta}d",
                              f"Inv: {t_avail} units at {req.toFactoryId}",
                              f"+$1.00 transfer overhead + expedite"]),
    ]

    scored = [(sc, sc.eta_delta_days + sc.line_stop_risk * 20) for sc in scenarios]
    if req.objective == "cost-first":
        scored = [(sc, sc.cost_delta_pct + sc.line_stop_risk * 20) for sc in scenarios]
    recommended = min(scored, key=lambda x: x[1])[0].label

    return SimulationResult(
        scenarios=scenarios, recommended=recommended, blastRadius=blast,
        assumptions=[f"From {from_fid}, To {req.toFactoryId}", f"Ramp-up {ramp_up_days}d"],
    )


# ────────────────────────────────────────────────────────────────────
# GET /blast-radius
# ────────────────────────────────────────────────────────────────────

@app.get("/blast-radius", response_model=BlastRadius)
def blast_radius(
    orderId: str | None = None,
    supplierId: str | None = None,
    partId: str | None = None,
) -> BlastRadius:
    if not any([orderId, supplierId, partId]):
        raise HTTPException(400, "Provide at least one of orderId, supplierId, partId")
    with _driver.session() as s:
        return s.execute_read(_blast_radius, orderId, supplierId, partId)
