"""Agent-API – Multi-agent workflow: plan → analyze → simulate → execute + sourcing."""

from __future__ import annotations

import math
import os
import uuid
from datetime import date, datetime, timezone
from typing import Optional

import httpx
import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# ────────────────────────────────────────────────────────────────────
# App + config
# ────────────────────────────────────────────────────────────────────

app = FastAPI(title="Agent-API", version="0.1.0")

ERP_DSN = os.getenv(
    "ERP_DSN",
    "host=postgres_erp port=5432 dbname=erp user=demo password=demo",
)
TWIN_SIM_URL = os.getenv("TWIN_SIM_URL", "http://twin-sim:7100")
GRAPHQL_URL = os.getenv("GRAPHQL_URL", "http://graphql-api:4000")


def _erp_conn():
    return psycopg2.connect(ERP_DSN)


@app.get("/healthz")
def healthz() -> dict:
    """Basic liveness check – also verifies Postgres connectivity."""
    try:
        conn = _erp_conn()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return {"status": "ok", "erp": "connected"}
    except Exception as exc:
        raise HTTPException(503, f"ERP unreachable: {exc}")


# ────────────────────────────────────────────────────────────────────
# Pydantic models
# ────────────────────────────────────────────────────────────────────

# --- Integrator (plan) ---

class PlanRequest(BaseModel):
    question: str
    lang: str = "en"


class PlanStep(BaseModel):
    step: int
    role: str
    action: str
    description: str


class PlanResponse(BaseModel):
    intent: str
    steps: list[PlanStep]


# --- Analyst (analyze) ---

class AnalyzeRequest(BaseModel):
    orderId: Optional[str] = None
    partId: Optional[str] = None
    supplierId: Optional[str] = None


class AnalyzeResponse(BaseModel):
    summary: str
    metrics: dict
    rootCause: str


# --- Simulator (simulate) ---

class SimulateRequest(BaseModel):
    orderId: str
    partId: str
    toSupplierId: str
    objective: str = "delivery-first"


class SimulateResponse(BaseModel):
    scenarios: list[dict]
    recommended: str
    rationale: str
    blastRadius: dict


# --- Action (execute) ---

class ExecuteRequest(BaseModel):
    action: str  # CREATE_PO | EXPEDITE_SHIPMENT
    partId: Optional[str] = None
    supplierId: Optional[str] = None
    qty: Optional[int] = None
    orderId: Optional[str] = None
    poId: Optional[str] = None
    newMode: Optional[str] = None
    actor: str = "agent-system"


class ExecuteResponse(BaseModel):
    success: bool
    message: str
    auditEventId: Optional[str] = None
    actionRequestId: Optional[str] = None
    details: Optional[dict] = None


# ────────────────────────────────────────────────────────────────────
# Role 1: Integrator – POST /agent/plan
# Rule-based intent classification → step list
# ────────────────────────────────────────────────────────────────────

INTENT_KEYWORDS = {
    "RFQ": [
        "rfq", "候选", "寻源", "评分", "排序", "供应商评分",
        "candidate", "sourcing", "scorecard", "ranking",
    ],
    "SINGLE_SOURCE": [
        "单一来源", "single source", "single-source", "sole source",
        "瓶颈件", "关键件",
    ],
    "CONSOLIDATE_PO": [
        "moq", "合并采购", "合并下单", "分摊", "分配方案",
        "consolidat", "allocation",
    ],
    "CREATE_PO": [
        "create po", "new purchase order", "order from", "buy from",
        "采购", "下单", "新建采购单", "create purchase",
    ],
    "EXPEDITE_SHIPMENT": [
        "expedite", "speed up", "air freight", "change mode",
        "加急", "空运", "改运输", "加速发货",
    ],
    "SWITCH_SUPPLIER": [
        "switch supplier", "change supplier", "换供应商", "切换供应商",
    ],
    "ANALYZE_RISK": [
        "risk", "analyze", "what happened", "root cause",
        "风险", "分析", "根因",
    ],
}


@app.post("/agent/plan", response_model=PlanResponse)
def plan(req: PlanRequest) -> PlanResponse:
    q = req.question.lower()
    intent = "UNKNOWN"
    for key, keywords in INTENT_KEYWORDS.items():
        if any(kw in q for kw in keywords):
            intent = key
            break

    steps: list[PlanStep] = []
    step_num = 1

    if intent == "RFQ":
        steps.append(PlanStep(step=step_num, role="sourcing", action="rfq-candidates",
                              description="Score and rank supplier candidates for RFQ"))
        step_num += 1
        steps.append(PlanStep(step=step_num, role="action", action="execute",
                              description="Optionally create PO from top recommendation"))
    elif intent == "SINGLE_SOURCE":
        steps.append(PlanStep(step=step_num, role="sourcing", action="single-source-parts",
                              description="Identify single-source critical parts with risk"))
    elif intent == "CONSOLIDATE_PO":
        steps.append(PlanStep(step=step_num, role="sourcing", action="consolidate-po",
                              description="Consolidate demand to meet MOQ with allocation plan"))
    elif intent in ("CREATE_PO", "EXPEDITE_SHIPMENT"):
        steps.append(PlanStep(step=step_num, role="analyst", action="analyze",
                              description="Gather order/risk/inventory context"))
        step_num += 1
        if intent == "CREATE_PO":
            steps.append(PlanStep(step=step_num, role="simulator", action="simulate",
                                  description="Run what-if simulation for supplier switch"))
            step_num += 1
        steps.append(PlanStep(step=step_num, role="action", action="execute",
                              description=f"Execute {intent} with qualification check"))
        step_num += 1
        steps.append(PlanStep(step=step_num, role="audit", action="verify",
                              description="Verify audit trail recorded"))
    elif intent == "SWITCH_SUPPLIER":
        steps.append(PlanStep(step=step_num, role="analyst", action="analyze",
                              description="Gather current supplier context"))
        step_num += 1
        steps.append(PlanStep(step=step_num, role="simulator", action="simulate",
                              description="Run switch-supplier simulation"))
        step_num += 1
        steps.append(PlanStep(step=step_num, role="action", action="execute",
                              description="Execute CREATE_PO for new supplier"))
        step_num += 1
        steps.append(PlanStep(step=step_num, role="audit", action="verify",
                              description="Verify audit trail recorded"))
    elif intent == "ANALYZE_RISK":
        steps.append(PlanStep(step=step_num, role="analyst", action="analyze",
                              description="Gather risk and inventory context"))
        step_num += 1
        steps.append(PlanStep(step=step_num, role="simulator", action="simulate",
                              description="Simulate mitigation options"))
    else:
        steps.append(PlanStep(step=step_num, role="analyst", action="analyze",
                              description="Gather general context for the question"))

    return PlanResponse(intent=intent, steps=steps)


# ────────────────────────────────────────────────────────────────────
# Role 2: Analyst – POST /agent/analyze
# Gathers context from graphql-api + ERP, composes explanation
# ────────────────────────────────────────────────────────────────────

@app.post("/agent/analyze", response_model=AnalyzeResponse)
async def analyze(req: AnalyzeRequest) -> AnalyzeResponse:
    metrics: dict = {}
    root_parts: list[str] = []

    # Fetch order context from GraphQL
    if req.orderId:
        gql = (
            '{ orders(where: { id: "%s" }) { id status requires { id name '
            "suppliedBy { id name } } } }" % req.orderId
        )
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    f"{GRAPHQL_URL}/graphql",
                    json={"query": gql},
                )
                data = resp.json().get("data", {})
                orders = data.get("orders", [])
                if orders:
                    order = orders[0]
                    metrics["orderStatus"] = order.get("status", "unknown")
                    parts = order.get("requires", [])
                    metrics["requiredParts"] = len(parts)
                    for p in parts:
                        suppliers = p.get("suppliedBy", [])
                        if len(suppliers) <= 1:
                            root_parts.append(p.get("id", "?"))
        except Exception:
            pass

    # Fetch risk events from GraphQL
    if req.supplierId:
        gql = (
            '{ suppliers(where: { id: "%s" }) { id name affectedBy { id type severity } } }'
            % req.supplierId
        )
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.post(
                    f"{GRAPHQL_URL}/graphql",
                    json={"query": gql},
                )
                data = resp.json().get("data", {})
                suppliers = data.get("suppliers", [])
                if suppliers:
                    risks = suppliers[0].get("affectedBy", [])
                    metrics["activeRisks"] = len(risks)
                    if risks:
                        metrics["maxSeverity"] = max(
                            r.get("severity", 0) for r in risks
                        )
        except Exception:
            pass

    # Fetch ERP inventory for the part
    if req.partId:
        try:
            conn = _erp_conn()
            cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
            cur.execute(
                "SELECT SUM(on_hand) AS on_hand, SUM(reserved) AS reserved "
                "FROM inventory_lots WHERE part_id = %s",
                (req.partId,),
            )
            row = cur.fetchone()
            if row and row["on_hand"] is not None:
                metrics["onHand"] = int(row["on_hand"])
                metrics["reserved"] = int(row["reserved"])
                metrics["available"] = int(row["on_hand"]) - int(row["reserved"])
            cur.close()
            conn.close()
        except Exception:
            pass

    # Compose root-cause explanation
    causes: list[str] = []
    if root_parts:
        causes.append(f"Single-source parts: {', '.join(root_parts)}")
    if metrics.get("activeRisks", 0) > 0:
        causes.append(
            f"Supplier has {metrics['activeRisks']} active risk event(s) "
            f"(max severity {metrics.get('maxSeverity', '?')})"
        )
    avail = metrics.get("available")
    if avail is not None and avail < 100:
        causes.append(f"Low available inventory: {avail} units")

    root_cause = "; ".join(causes) if causes else "No immediate root cause identified"
    summary = (
        f"Analysis for order={req.orderId or 'N/A'}, part={req.partId or 'N/A'}, "
        f"supplier={req.supplierId or 'N/A'}. {root_cause}."
    )

    return AnalyzeResponse(summary=summary, metrics=metrics, rootCause=root_cause)


# ────────────────────────────────────────────────────────────────────
# Role 3: Simulator – POST /agent/simulate
# Wraps twin-sim switch-supplier + adds rationale
# ────────────────────────────────────────────────────────────────────

@app.post("/agent/simulate", response_model=SimulateResponse)
async def simulate(req: SimulateRequest) -> SimulateResponse:
    body = {
        "orderId": req.orderId,
        "partId": req.partId,
        "toSupplierId": req.toSupplierId,
        "objective": req.objective,
    }
    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.post(
                f"{TWIN_SIM_URL}/simulate/switch-supplier",
                json=body,
            )
            if resp.status_code != 200:
                raise HTTPException(resp.status_code, resp.text)
            data = resp.json()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(502, f"twin-sim error: {exc}")
    except httpx.RequestError as exc:
        raise HTTPException(502, f"twin-sim unreachable: {exc}")

    scenarios = data.get("scenarios", [])
    recommended = data.get("recommended", "")
    blast_radius = data.get("blastRadius", {})

    # Build human-readable rationale
    rec_scenario = next((s for s in scenarios if s.get("label") == recommended), None)
    if rec_scenario:
        rationale = (
            f"Recommended scenario {recommended} "
            f"({rec_scenario.get('description', '')}) — "
            f"ETA delta: {rec_scenario.get('eta_delta_days', 0)}d, "
            f"cost delta: {rec_scenario.get('cost_delta_pct', 0)}%, "
            f"line-stop risk: {rec_scenario.get('line_stop_risk', 0):.0%}, "
            f"quality risk: {rec_scenario.get('quality_risk', 0):.0%}."
        )
    else:
        rationale = f"Recommended scenario: {recommended}"

    return SimulateResponse(
        scenarios=scenarios,
        recommended=recommended,
        rationale=rationale,
        blastRadius=blast_radius,
    )


# ────────────────────────────────────────────────────────────────────
# Role 4: Action – POST /agent/execute
# Writeback to ERP + audit trail
# ────────────────────────────────────────────────────────────────────

def _write_audit(conn, event_id: str, actor: str, action: str,
                 input_data: dict, output_data: dict, status: str) -> None:
    cur = conn.cursor()
    cur.execute(
        """INSERT INTO audit_events (event_id, ts, actor, action, input, output, status)
           VALUES (%s, %s, %s, %s, %s, %s, %s)""",
        (
            event_id,
            datetime.now(timezone.utc),
            actor,
            action,
            psycopg2.extras.Json(input_data),
            psycopg2.extras.Json(output_data),
            status,
        ),
    )
    cur.close()


def _write_action_request(conn, request_id: str, action_type: str,
                          payload: dict, approval: str = "auto-approved") -> None:
    cur = conn.cursor()
    cur.execute(
        """INSERT INTO action_requests (request_id, type, payload, approval_status, created_at)
           VALUES (%s, %s, %s, %s, %s)""",
        (
            request_id,
            action_type,
            psycopg2.extras.Json(payload),
            approval,
            datetime.now(timezone.utc),
        ),
    )
    cur.close()


@app.post("/agent/execute", response_model=ExecuteResponse)
def execute(req: ExecuteRequest) -> ExecuteResponse:
    if req.action == "CREATE_PO":
        return _execute_create_po(req)
    elif req.action == "EXPEDITE_SHIPMENT":
        return _execute_expedite_shipment(req)
    else:
        raise HTTPException(400, f"Unknown action: {req.action}")


def _execute_create_po(req: ExecuteRequest) -> ExecuteResponse:
    if not req.partId or not req.supplierId or not req.qty:
        raise HTTPException(
            400, "CREATE_PO requires partId, supplierId, and qty",
        )

    event_id = f"AE-{uuid.uuid4().hex[:8]}"
    request_id = f"AR-{uuid.uuid4().hex[:8]}"
    input_data = {
        "action": "CREATE_PO",
        "partId": req.partId,
        "supplierId": req.supplierId,
        "qty": req.qty,
        "orderId": req.orderId,
    }

    conn = _erp_conn()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Qualification check: supplier must be approved
        cur.execute(
            "SELECT approved FROM suppliers WHERE supplier_id = %s",
            (req.supplierId,),
        )
        supplier_row = cur.fetchone()
        if not supplier_row:
            _write_audit(
                conn, event_id, req.actor, "CREATE_PO",
                input_data, {"reason": "Supplier not found"}, "rejected",
            )
            conn.commit()
            return ExecuteResponse(
                success=False,
                message=f"Rejected: supplier {req.supplierId} not found in ERP",
                auditEventId=event_id,
            )
        if not supplier_row["approved"]:
            _write_audit(
                conn, event_id, req.actor, "CREATE_PO",
                input_data, {"reason": "Supplier not approved"}, "rejected",
            )
            conn.commit()
            return ExecuteResponse(
                success=False,
                message=f"Rejected: supplier {req.supplierId} is not approved",
                auditEventId=event_id,
            )

        # Qualification check: supplier must supply the part
        cur.execute(
            "SELECT 1 FROM supplier_parts WHERE supplier_id = %s AND part_id = %s",
            (req.supplierId, req.partId),
        )
        if not cur.fetchone():
            _write_audit(
                conn, event_id, req.actor, "CREATE_PO",
                input_data,
                {"reason": f"Supplier {req.supplierId} does not supply part {req.partId}"},
                "rejected",
            )
            conn.commit()
            return ExecuteResponse(
                success=False,
                message=f"Rejected: supplier {req.supplierId} does not supply part {req.partId}",
                auditEventId=event_id,
            )

        # Generate PO ID
        cur.execute("SELECT COUNT(*) AS cnt FROM purchase_orders")
        count = cur.fetchone()["cnt"]
        po_id = f"PO-AGENT-{count + 1:04d}"

        # Insert purchase order
        cur.execute(
            """INSERT INTO purchase_orders (po_id, part_id, supplier_id, qty, status, eta, updated_at)
               VALUES (%s, %s, %s, %s, 'Open', CURRENT_DATE + INTERVAL '14 days', now())""",
            (po_id, req.partId, req.supplierId, req.qty),
        )

        output_data = {"poId": po_id, "status": "Open"}

        _write_audit(
            conn, event_id, req.actor, "CREATE_PO",
            input_data, output_data, "success",
        )
        _write_action_request(
            conn, request_id, "CREATE_PO",
            {**input_data, "poId": po_id},
        )

        conn.commit()
        cur.close()

        return ExecuteResponse(
            success=True,
            message=f"Purchase order {po_id} created for {req.qty}x {req.partId} from {req.supplierId}",
            auditEventId=event_id,
            actionRequestId=request_id,
            details=output_data,
        )
    except Exception as exc:
        conn.rollback()
        raise HTTPException(500, f"CREATE_PO failed: {exc}")
    finally:
        conn.close()


def _execute_expedite_shipment(req: ExecuteRequest) -> ExecuteResponse:
    if not req.poId:
        raise HTTPException(400, "EXPEDITE_SHIPMENT requires poId")

    new_mode = req.newMode or "Air"
    event_id = f"AE-{uuid.uuid4().hex[:8]}"
    request_id = f"AR-{uuid.uuid4().hex[:8]}"
    input_data = {
        "action": "EXPEDITE_SHIPMENT",
        "poId": req.poId,
        "newMode": new_mode,
    }

    conn = _erp_conn()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Find shipment for the PO
        cur.execute(
            "SELECT shipment_id, mode, status, eta FROM shipments WHERE po_id = %s",
            (req.poId,),
        )
        shipment = cur.fetchone()
        if not shipment:
            _write_audit(
                conn, event_id, req.actor, "EXPEDITE_SHIPMENT",
                input_data, {"reason": "No shipment found for PO"}, "rejected",
            )
            conn.commit()
            return ExecuteResponse(
                success=False,
                message=f"Rejected: no shipment found for PO {req.poId}",
                auditEventId=event_id,
            )

        old_mode = shipment["mode"]
        old_eta = str(shipment["eta"]) if shipment["eta"] else None

        # Update shipment mode and adjust ETA
        cur.execute(
            """UPDATE shipments
               SET mode = %s,
                   eta = CURRENT_DATE + INTERVAL '3 days',
                   updated_at = now()
               WHERE po_id = %s""",
            (new_mode, req.poId),
        )

        # Fetch updated ETA
        cur.execute(
            "SELECT eta FROM shipments WHERE po_id = %s", (req.poId,),
        )
        new_eta_row = cur.fetchone()
        new_eta = str(new_eta_row["eta"]) if new_eta_row and new_eta_row["eta"] else None

        output_data = {
            "shipmentId": shipment["shipment_id"],
            "oldMode": old_mode,
            "newMode": new_mode,
            "oldEta": old_eta,
            "newEta": new_eta,
        }

        _write_audit(
            conn, event_id, req.actor, "EXPEDITE_SHIPMENT",
            input_data, output_data, "success",
        )
        _write_action_request(
            conn, request_id, "EXPEDITE_SHIPMENT",
            {**input_data, "shipmentId": shipment["shipment_id"]},
        )

        conn.commit()
        cur.close()

        return ExecuteResponse(
            success=True,
            message=(
                f"Shipment {shipment['shipment_id']} expedited: "
                f"{old_mode} → {new_mode}, ETA {old_eta} → {new_eta}"
            ),
            auditEventId=event_id,
            actionRequestId=request_id,
            details=output_data,
        )
    except Exception as exc:
        conn.rollback()
        raise HTTPException(500, f"EXPEDITE_SHIPMENT failed: {exc}")
    finally:
        conn.close()


# ════════════════════════════════════════════════════════════════════
# Sprint 4 — Sourcing: RFQ Candidates, Single-Source, MOQ Consolidation
# ════════════════════════════════════════════════════════════════════

# ── Scoring weights by objective ──

OBJECTIVE_WEIGHTS = {
    "delivery-first":   {"lead": 0.40, "cost": 0.15, "risk": 0.25, "lane": 0.20},
    "cost-first":       {"lead": 0.20, "cost": 0.40, "risk": 0.20, "lane": 0.20},
    "resilience-first": {"lead": 0.15, "cost": 0.15, "risk": 0.50, "lane": 0.20},
    "balanced":         {"lead": 0.25, "cost": 0.25, "risk": 0.25, "lane": 0.25},
}

QUAL_SCORE_MAP = {"Full": 90, "Conditional": 55, "Pending": 25, "Disqualified": 0}


# ── Pydantic models ──

class RfqRequest(BaseModel):
    partId: str
    factoryId: str = "F1"
    qty: int = 1000
    needByDate: Optional[str] = None  # ISO date string; defaults to +30 days
    objective: str = "balanced"


class CandidateBreakdown(BaseModel):
    lead: float
    cost: float
    risk: float
    lane: float
    penalties: float


class RfqCandidate(BaseModel):
    rank: int
    supplierId: str
    supplierName: str
    totalScore: float
    breakdown: CandidateBreakdown
    explanations: list[str]
    recommendedActions: list[str]
    hardFail: bool = False
    hardFailReason: Optional[str] = None


class RfqResponse(BaseModel):
    partId: str
    qty: int
    objective: str
    candidates: list[RfqCandidate]


class SingleSourceRequest(BaseModel):
    threshold: int = 1


class SingleSourcePart(BaseModel):
    partId: str
    partName: str
    supplierCount: int
    suppliers: list[dict]
    riskExplanation: str
    recommendation: str


class SingleSourceResponse(BaseModel):
    parts: list[SingleSourcePart]


class ConsolidateRequest(BaseModel):
    partId: str
    horizonDays: int = 30
    policy: str = "priority"  # priority | earliest_due | risk_min


class AllocationItem(BaseModel):
    orderId: str
    qty: int
    needByDate: str
    priority: int


class ConsolidateResponse(BaseModel):
    partId: str
    totalDemand: int
    consolidatedQty: int
    supplierId: str
    supplierName: str
    moq: int
    unitPrice: float
    allocations: list[AllocationItem]
    explanation: str


# ── POST /agent/rfq-candidates ──

@app.post("/agent/rfq-candidates", response_model=RfqResponse)
def rfq_candidates(req: RfqRequest) -> RfqResponse:
    weights = OBJECTIVE_WEIGHTS.get(req.objective, OBJECTIVE_WEIGHTS["balanced"])

    if req.needByDate:
        need_by = date.fromisoformat(req.needByDate)
    else:
        need_by = date.today() + __import__("datetime").timedelta(days=30)

    days_available = max((need_by - date.today()).days, 1)

    conn = _erp_conn()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Get all suppliers for this part
        cur.execute("""
            SELECT sp.supplier_id, s.name AS supplier_name, s.approved,
                   sp.lead_time_days, sp.moq, sp.capacity_per_week,
                   sp.last_price, sp.qualification_level, sp.priority
            FROM supplier_parts sp
            JOIN suppliers s ON s.supplier_id = sp.supplier_id
            WHERE sp.part_id = %s
            ORDER BY sp.priority, sp.last_price
        """, (req.partId,))
        suppliers = cur.fetchall()

        if not suppliers:
            return RfqResponse(partId=req.partId, qty=req.qty,
                               objective=req.objective, candidates=[])

        # Get transport lanes for each supplier → factory
        lane_map: dict[str, dict] = {}
        for sp in suppliers:
            cur.execute("""
                SELECT mode, time_days, cost, reliability
                FROM transport_lanes
                WHERE supplier_id = %s AND factory_id = %s
                ORDER BY time_days
                LIMIT 1
            """, (sp["supplier_id"], req.factoryId))
            lane = cur.fetchone()
            if lane:
                lane_map[sp["supplier_id"]] = dict(lane)
            else:
                lane_map[sp["supplier_id"]] = {
                    "mode": "Ocean", "time_days": 21, "cost": 1.00, "reliability": 0.85,
                }

        # Get existing quotes
        cur.execute("""
            SELECT supplier_id, price, valid_to, incoterms
            FROM quotes
            WHERE part_id = %s AND valid_to >= CURRENT_DATE
            ORDER BY price
        """, (req.partId,))
        quote_map: dict[str, dict] = {}
        for q in cur.fetchall():
            if q["supplier_id"] not in quote_map:
                quote_map[q["supplier_id"]] = dict(q)

        # Count total qualified suppliers for this part (for risk calc)
        total_suppliers = sum(1 for sp in suppliers
                              if sp["qualification_level"] != "Disqualified"
                              and sp["approved"])

        cur.close()
    finally:
        conn.close()

    # Find min cost for normalization
    costs = []
    for sp in suppliers:
        lane = lane_map[sp["supplier_id"]]
        quote = quote_map.get(sp["supplier_id"])
        unit_price = float(quote["price"]) if quote else float(sp["last_price"])
        total_cost = unit_price + float(lane["cost"])
        costs.append(total_cost)
    min_cost = min(costs) if costs else 1.0

    # Score each candidate
    raw_candidates: list[RfqCandidate] = []
    for idx, sp in enumerate(suppliers):
        sid = sp["supplier_id"]
        sname = sp["supplier_name"]
        lane = lane_map[sid]
        quote = quote_map.get(sid)
        explanations: list[str] = []
        actions: list[str] = []
        penalties = 0.0
        hard_fail = False
        hard_fail_reason = None

        lead_days = int(sp["lead_time_days"])
        transit_days = int(lane["time_days"])
        total_delivery = lead_days + transit_days
        unit_price = float(quote["price"]) if quote else float(sp["last_price"])
        total_cost = unit_price + float(lane["cost"])
        qual = sp["qualification_level"] or "Pending"
        moq = int(sp["moq"]) if sp["moq"] else 100
        capacity = int(sp["capacity_per_week"]) if sp["capacity_per_week"] else 5000
        reliability = float(lane["reliability"])

        # -- Lead time score (0-100) --
        if total_delivery <= days_available:
            margin = days_available - total_delivery
            lead_score = min(100, 60 + margin * 2)
        else:
            overshoot = total_delivery - days_available
            lead_score = max(0, 50 - overshoot * 5)
        explanations.append(
            f"Lead: {lead_days}d production + {transit_days}d {lane['mode']} "
            f"= {total_delivery}d (need by {need_by}, {days_available - total_delivery}d margin)"
        )

        # Hard constraint: delivery impossible
        if total_delivery > days_available * 1.5:
            hard_fail = True
            hard_fail_reason = (
                f"Cannot deliver in time: {total_delivery}d vs {days_available}d available"
            )

        # -- Cost score (0-100) --
        cost_score = round(100 * (min_cost / total_cost), 1) if total_cost > 0 else 0
        price_src = "quoted" if quote else "catalog"
        explanations.append(
            f"Cost: ${unit_price:.2f}/unit ({price_src}) + "
            f"${float(lane['cost']):.2f} shipping = ${total_cost:.2f}/unit "
            f"({'+' if total_cost > min_cost else ''}{((total_cost - min_cost) / min_cost * 100):.0f}% vs cheapest)"
        )

        # -- Risk score (0-100) --
        risk_base = QUAL_SCORE_MAP.get(qual, 30)
        multi_source_bonus = 5 if total_suppliers >= 2 else 0
        risk_score = min(100, risk_base + multi_source_bonus)
        explanations.append(
            f"Risk: qualification={qual} (base {risk_base}), "
            f"{total_suppliers} qualified source(s)"
        )

        # Hard constraint: disqualified or not approved
        if qual == "Disqualified":
            hard_fail = True
            hard_fail_reason = "Supplier is disqualified"
        if not sp["approved"]:
            hard_fail = True
            hard_fail_reason = f"Supplier {sid} is not approved"

        # -- Lane score (0-100) --
        lane_score = round(reliability * 100, 1)
        explanations.append(
            f"Lane: {lane['mode']} to {req.factoryId}, "
            f"reliability {reliability:.0%}, {transit_days}d"
        )

        # -- Penalties --
        if req.qty < moq:
            penalties -= 10
            explanations.append(
                f"PENALTY: MOQ={moq}, requested {req.qty}. "
                f"Gap of {moq - req.qty} units."
            )
            actions.append(
                f"Consider consolidating with other orders to meet MOQ of {moq}. "
                f"Use /consolidate-po for allocation plan."
            )

        if req.qty > capacity * 2:
            penalties -= 15
            explanations.append(
                f"PENALTY: weekly capacity={capacity}, "
                f"order qty={req.qty} exceeds 2-week capacity"
            )
            actions.append("Consider splitting order across multiple suppliers")

        if qual == "Conditional":
            actions.append(f"Accelerate full qualification for {sid}")
        elif qual == "Pending":
            penalties -= 8
            actions.append(
                f"Supplier {sid} needs qualification — "
                f"estimated 4-6 weeks to complete"
            )

        # -- Total weighted score --
        total_score = round(
            lead_score * weights["lead"]
            + cost_score * weights["cost"]
            + risk_score * weights["risk"]
            + lane_score * weights["lane"]
            + penalties,
            2,
        )

        raw_candidates.append(RfqCandidate(
            rank=0,
            supplierId=sid,
            supplierName=sname,
            totalScore=total_score,
            breakdown=CandidateBreakdown(
                lead=round(lead_score * weights["lead"], 2),
                cost=round(cost_score * weights["cost"], 2),
                risk=round(risk_score * weights["risk"], 2),
                lane=round(lane_score * weights["lane"], 2),
                penalties=penalties,
            ),
            explanations=explanations,
            recommendedActions=actions,
            hardFail=hard_fail,
            hardFailReason=hard_fail_reason,
        ))

    # Sort: non-hard-fail first, then by score desc
    raw_candidates.sort(key=lambda c: (c.hardFail, -c.totalScore))
    for i, c in enumerate(raw_candidates):
        c.rank = i + 1

    return RfqResponse(
        partId=req.partId, qty=req.qty,
        objective=req.objective, candidates=raw_candidates,
    )


# ── POST /agent/single-source-parts ──

@app.post("/agent/single-source-parts", response_model=SingleSourceResponse)
def single_source_parts(req: SingleSourceRequest) -> SingleSourceResponse:
    conn = _erp_conn()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute("""
            SELECT p.part_id, p.name AS part_name,
                   COUNT(DISTINCT CASE WHEN s.approved AND sp.qualification_level IN ('Full','Conditional')
                         THEN sp.supplier_id END) AS qualified_count,
                   COUNT(DISTINCT sp.supplier_id) AS total_count
            FROM parts p
            JOIN supplier_parts sp ON sp.part_id = p.part_id
            JOIN suppliers s ON s.supplier_id = sp.supplier_id
            GROUP BY p.part_id, p.name
            HAVING COUNT(DISTINCT CASE WHEN s.approved AND sp.qualification_level IN ('Full','Conditional')
                         THEN sp.supplier_id END) <= %s
            ORDER BY COUNT(DISTINCT CASE WHEN s.approved AND sp.qualification_level IN ('Full','Conditional')
                         THEN sp.supplier_id END),
                     p.part_id
        """, (req.threshold,))
        parts_rows = cur.fetchall()

        result: list[SingleSourcePart] = []
        for row in parts_rows:
            pid = row["part_id"]
            # Get supplier details
            cur.execute("""
                SELECT sp.supplier_id, s.name, sp.qualification_level, s.approved,
                       sp.lead_time_days, sp.last_price, sp.capacity_per_week
                FROM supplier_parts sp
                JOIN suppliers s ON s.supplier_id = sp.supplier_id
                WHERE sp.part_id = %s
                ORDER BY sp.priority
            """, (pid,))
            suppliers = [dict(r) for r in cur.fetchall()]

            # Count demand orders for this part
            cur.execute(
                "SELECT COUNT(DISTINCT order_id) AS order_count FROM demand WHERE part_id = %s",
                (pid,),
            )
            demand_row = cur.fetchone()
            order_count = int(demand_row["order_count"]) if demand_row else 0

            qualified = [s for s in suppliers
                         if s["approved"] and s["qualification_level"] in ("Full", "Conditional")]
            q_count = int(row["qualified_count"])

            # Risk explanation
            if q_count == 0:
                risk = (f"CRITICAL: No qualified supplier for {pid}. "
                        f"{len(suppliers)} supplier(s) exist but none are fully qualified/approved.")
            elif q_count == 1:
                sole = qualified[0]
                risk = (f"HIGH: Single qualified source {sole['supplier_id']} ({sole['name']}), "
                        f"qual={sole['qualification_level']}. "
                        f"Used by {order_count} order(s). Any disruption = line stop.")
            else:
                risk = (f"MODERATE: Only {q_count} qualified sources. "
                        f"Used by {order_count} order(s).")

            # Recommendation
            pending = [s for s in suppliers if s["qualification_level"] == "Pending"]
            if pending:
                rec = (f"Accelerate qualification of {', '.join(s['supplier_id'] for s in pending)} "
                       f"to develop second source. "
                       f"Estimated 4-6 weeks for full qualification.")
            elif q_count <= 1:
                rec = (f"Initiate RFQ with alternative suppliers. "
                       f"Consider regional diversification to reduce logistics risk.")
            else:
                rec = "Monitor existing supply base; consider qualifying a third source."

            result.append(SingleSourcePart(
                partId=pid,
                partName=row["part_name"],
                supplierCount=q_count,
                suppliers=[{
                    "supplierId": s["supplier_id"],
                    "name": s["name"],
                    "qualification": s["qualification_level"],
                    "approved": s["approved"],
                } for s in suppliers],
                riskExplanation=risk,
                recommendation=rec,
            ))

        cur.close()
    finally:
        conn.close()

    return SingleSourceResponse(parts=result)


# ── POST /agent/consolidate-po ──

@app.post("/agent/consolidate-po", response_model=ConsolidateResponse)
def consolidate_po(req: ConsolidateRequest) -> ConsolidateResponse:
    conn = _erp_conn()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # Get demand within horizon
        cur.execute("""
            SELECT order_id, qty, need_by_date, priority, factory_id
            FROM demand
            WHERE part_id = %s
              AND need_by_date <= CURRENT_DATE + (%s || ' days')::INTERVAL
            ORDER BY priority, need_by_date
        """, (req.partId, str(req.horizonDays)))
        demands = cur.fetchall()

        if not demands:
            raise HTTPException(404, f"No demand found for {req.partId} within {req.horizonDays} days")

        total_demand = sum(int(d["qty"]) for d in demands)

        # Get best supplier (priority 1, Full qualification, approved)
        cur.execute("""
            SELECT sp.supplier_id, s.name, sp.moq, sp.last_price,
                   sp.capacity_per_week, sp.qualification_level
            FROM supplier_parts sp
            JOIN suppliers s ON s.supplier_id = sp.supplier_id
            WHERE sp.part_id = %s AND s.approved = true
                  AND sp.qualification_level IN ('Full', 'Conditional')
            ORDER BY sp.priority, sp.last_price
            LIMIT 1
        """, (req.partId,))
        best_supplier = cur.fetchone()

        if not best_supplier:
            raise HTTPException(404, f"No qualified supplier found for {req.partId}")

        moq = int(best_supplier["moq"])
        consolidated_qty = max(total_demand, moq)
        # Round up to MOQ multiple
        if moq > 0 and consolidated_qty % moq != 0:
            consolidated_qty = math.ceil(consolidated_qty / moq) * moq

        # Sort demands by policy
        sorted_demands = list(demands)
        if req.policy == "earliest_due":
            sorted_demands.sort(key=lambda d: d["need_by_date"])
        elif req.policy == "risk_min":
            sorted_demands.sort(key=lambda d: (d["priority"], d["need_by_date"]))
        else:  # priority (default)
            sorted_demands.sort(key=lambda d: (d["priority"], d["need_by_date"]))

        # Build allocation plan
        remaining = consolidated_qty
        allocations: list[AllocationItem] = []
        for d in sorted_demands:
            alloc_qty = min(int(d["qty"]), remaining)
            if alloc_qty <= 0:
                continue
            allocations.append(AllocationItem(
                orderId=d["order_id"],
                qty=alloc_qty,
                needByDate=str(d["need_by_date"]),
                priority=int(d["priority"]),
            ))
            remaining -= alloc_qty

        # Explanation
        surplus = consolidated_qty - total_demand
        explanation_parts = [
            f"Total demand: {total_demand} units across {len(demands)} order(s) "
            f"within {req.horizonDays}-day horizon.",
        ]
        if total_demand < moq:
            explanation_parts.append(
                f"Individual demand ({total_demand}) below MOQ ({moq}). "
                f"Consolidated order raised to {consolidated_qty} units."
            )
        if surplus > 0:
            explanation_parts.append(
                f"Surplus of {surplus} units can buffer safety stock."
            )
        explanation_parts.append(
            f"Best supplier: {best_supplier['supplier_id']} ({best_supplier['name']}), "
            f"${float(best_supplier['last_price']):.2f}/unit, "
            f"qual={best_supplier['qualification_level']}."
        )
        explanation_parts.append(
            f"Allocation policy: {req.policy}."
        )

        cur.close()
    finally:
        conn.close()

    return ConsolidateResponse(
        partId=req.partId,
        totalDemand=total_demand,
        consolidatedQty=consolidated_qty,
        supplierId=best_supplier["supplier_id"],
        supplierName=best_supplier["name"],
        moq=moq,
        unitPrice=float(best_supplier["last_price"]),
        allocations=allocations,
        explanation=" ".join(explanation_parts),
    )
