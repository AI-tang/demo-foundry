"""Agent-API – Multi-agent workflow: plan → analyze → simulate → execute."""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone
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

    if intent in ("CREATE_PO", "EXPEDITE_SHIPMENT"):
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
