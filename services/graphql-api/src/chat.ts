import OpenAI from "openai";

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const PORT = parseInt(process.env.PORT ?? "4000", 10);
const TWIN_SIM_URL = process.env.TWIN_SIM_URL ?? "http://twin-sim:7100";
const AGENT_API_URL = process.env.AGENT_API_URL ?? "http://agent-api:7200";

// ────────────────────────────────────────────────────────────────────
// Schema description for NL→GraphQL
// ────────────────────────────────────────────────────────────────────

const SCHEMA_DESCRIPTION = `Available GraphQL Schema:

Types:
- Factory: id, name; relations: produces -> Product, canBackupWith -> Factory
- Supplier: id, name; relations: supplies -> Part (priority, leadTimeDays, moq, capacity, lastPrice, qualificationLevel), alternativeTo -> Supplier, affectedBy <- RiskEvent, lanes -> TransportLane
- Part: id, name, partType; relations: components -> Part, parentOf <- Part, suppliedBy <- Supplier, inventoryLots <- InventoryLot, deliveredBy <- Shipment
  IMPORTANT: Part does NOT have producedBy. Never use producedBy on Part.
- Product: id, name; relations: components -> Part, producedBy <- Factory, orders <- Order
  Note: producedBy ONLY exists on Product, not on Part.
- Order: id, status; relations: produces -> Product, requires -> Part, statuses -> SystemRecord
- SystemRecord: system, objectType, objectId, status, updatedAt
- RiskEvent: id, type, severity, date; relations: affects -> Supplier
- Shipment: id, mode, status, eta; relations: delivers -> Part
- InventoryLot: id, location, onHand, reserved, safetyStock; relations: stores -> Part
- TransportLane: id, fromNode, toNode, mode, timeDays, cost, reliability; relations: laneTo -> Factory
- QualityHold: id, supplierId, partId, holdDays, reason
- DefectEvent: id, description, severity, date; relations: affectsPart <- Part (HAS_DEFECT)
- ECO: id, description, status, date; relations: affectedParts -> Part (ECO_AFFECTS), replacementPart -> Part (ECO_REPLACES_WITH)

Custom Analysis Queries (场景分析):
- ordersAtRisk: 返回所有有风险的订单 / Returns all at-risk orders
- missingParts: 返回缺料零件 / Returns parts with zero available inventory
- lineStopForecast: 预测可能导致停线的订单 / Predicts orders that may cause line stops
- traceQuality(defectId: String!): 根据缺陷ID追溯影响 / Trace impact by defect ID
- ecoImpact(ecoId: String!): 根据ECO编号查影响范围 / Check impact scope by ECO ID
- reconcile: 返回跨系统状态不一致的订单 / Returns orders with cross-system status conflicts

Blast Radius Query:
- blastRadius(orderId: String, supplierId: String, partId: String): 返回影响范围 impactedOrders/impactedParts/impactedFactories/paths

Simulation Mutation (What-if):
- simulateSwitchSupplier(orderId, partId, toSupplierId, objective, constraints): 返回 scenarios (A/B/C) + recommended + blastRadius + assumptions
  用于"如果换供应商会怎样"类问题

Filter syntax (IMPORTANT — this schema does NOT use _EQ suffix for equality):
- Equality: field: "value"  (e.g. id: "SO1001", NOT id_EQ)
- List match: field_IN: ["a","b"]
- String: field_CONTAINS, field_STARTS_WITH, field_ENDS_WITH
- Numeric comparison: field_GT, field_GTE, field_LT, field_LTE
- Relation filters: relation_SOME, relation_ALL, relation_NONE (e.g. affectedBy_SOME: { severity_GTE: 1 })

Example mappings:

1. "What is the status of SO1001" / "SO1001 的状态是什么"
   Query: { orders(where: { id: "SO1001" }) { id status statuses { system status updatedAt } } }

2. "Which suppliers have risks" / "哪些供应商有风险"
   Query: { suppliers(where: { affectedBy_SOME: { severity_GTE: 1 } }) { id name affectedBy { id type severity date } } }

3. "Show all orders" / "显示所有订单"
   Query: { orders { id status produces { name } requires { name } statuses { system status } } }

4. "What are the components of BOM-1001" / "BOM-1001 的组件有哪些"
   Query: { parts(where: { id: "BOM-1001" }) { id name partType components { id name partType } } }

5. "Inventory status" / "库存情况"
   Query: { inventoryLots { id location onHand reserved safetyStock stores { id name } } }

6. "In-transit shipments" / "在途运输"
   Query: { shipments { id mode status eta delivers { id name } } }

7. "风险订单Top10" / "At-risk orders top 10"
   Query: { ordersAtRisk { id status } }
   Note: ordersAtRisk is a @cypher query — only request scalar fields (id, status), NOT nested relations.

8. "缺料零件" / "Missing parts"
   Query: { missingParts { id name partType } }
   Note: missingParts is a @cypher query — only request scalar fields (id, name, partType), NOT nested relations.

9. "追溯缺陷 D001" / "Trace defect D001"
   Query: { traceQuality(defectId: "D001") { id description severity } }
   Note: traceQuality is a @cypher query — only request scalar fields.

10. "ECO-1 影响哪些订单" / "ECO-1 impact"
    Query: { ecoImpact(ecoId: "ECO-1") { id description status } }
    Note: ecoImpact is a @cypher query — only request scalar fields.

11. "跨系统状态冲突" / "Cross-system conflicts"
    Query: { reconcile { id status } }
    Note: reconcile is a @cypher query — only request scalar fields (id, status), NOT nested relations.

12. "如果S1停产会影响什么" / "What if S1 shuts down"
    Query: { suppliers(where: { id: "S1" }) { id name supplies { id name parentOf { id name } } } }

13. "换供应商会影响哪些在制订单" / "Which in-progress orders are affected by supplier change"
    Query: { orders(where: { status_IN: ["InProgress", "AtRisk", "QualityHold"] }) { id status requires { id name suppliedBy { id name alternativeTo { id name } } } } }
    Note: Part does NOT have producedBy — that field only exists on Product. Use requires -> suppliedBy to trace supply chain.

14. "S1 的替代供应商是谁" / "Who are alternative suppliers for S1"
    Query: { suppliers(where: { id: "S1" }) { id name supplies { id name } alternativeTo { id name } } }

15. "SO1001 的影响范围" / "Blast radius of SO1001"
    Query: { blastRadius(orderId: "SO1001") { impactedOrders { id name type } impactedParts { id name type } impactedFactories { id name type } paths { from relation to } } }

16. "S1 的影响范围" / "Blast radius of supplier S1"
    Query: { blastRadius(supplierId: "S1") { impactedOrders { id name type } impactedParts { id name type } impactedFactories { id name type } paths { from relation to } } }

IMPORTANT: For custom @cypher queries (ordersAtRisk, missingParts, lineStopForecast, traceQuality, ecoImpact, reconcile), ONLY request scalar fields returned by the Cypher RETURN clause. Do NOT request nested relationship fields — they will fail.

Sourcing Queries (Sprint 4):
- rfqCandidates(partId, factoryId, qty, needByDate, objective): RFQ候选供应商排序评分 / RFQ candidate ranking with explainable scores
  objective: delivery-first / cost-first / resilience-first / balanced
- singleSourceParts(threshold): 单一来源关键件清单 / Single-source critical parts list
- consolidatePO(partId, horizonDays, policy): MOQ合并采购分配方案 / MOQ consolidation with allocation plan
  policy: priority / earliest_due / risk_min

Constraints:
- Only return JSON: { "query": "...", "variables": {} }
- The query must be valid GraphQL
- NEVER use _EQ suffix for equality filters. Use the field name directly (e.g. id: "value")
- Do not include any explanation, only return JSON
- If the user's question is vague, ambiguous, or not directly about data, try your best to infer a relevant query. For example "有什么解决方法" (any solutions) after discussing risks → query risk events and suppliers. If you truly cannot map it to any query, return: { "answer": "<a helpful reply>", "query": "", "variables": {} }`;

const SYSTEM_PROMPTS = {
  zh: `你是供应链 Control Tower 的数据分析助手。你的任务是将用户的自然语言问题转换为 GraphQL 查询。\n\n${SCHEMA_DESCRIPTION}`,
  en: `You are a supply chain Control Tower data analysis assistant. Your task is to convert user natural language questions into GraphQL queries.\n\n${SCHEMA_DESCRIPTION}`,
};

const SUMMARY_PROMPTS = {
  zh: "你是供应链数据分析助手。根据用户的问题和查询结果，用中文生成简洁的自然语言摘要。直接回答问题，不要提及 GraphQL。如果结果包含模拟场景(scenarios)，请用表格或列表清晰展示各方案的对比(ETA变化、成本变化、停线风险、质量风险)，并标注推荐方案。",
  en: "You are a supply chain data analysis assistant. Based on the user's question and query results, generate a concise natural language summary in English. Answer the question directly without mentioning GraphQL. If results contain simulation scenarios, present them in a clear comparison (ETA delta, cost delta, line stop risk, quality risk) and highlight the recommended option.",
};

const ERROR_MESSAGES = {
  zh: {
    parseFailed: "无法解析 AI 返回的查询，请尝试换一种表述。",
    queryError: "GraphQL 查询执行出错",
    execFailed: "查询执行失败",
    noSummary: "无法生成摘要。",
  },
  en: {
    parseFailed: "Unable to parse the AI response. Please try rephrasing your question.",
    queryError: "GraphQL query execution error",
    execFailed: "Query execution failed",
    noSummary: "Unable to generate summary.",
  },
};

export type Lang = "zh" | "en";

// ────────────────────────────────────────────────────────────────────
// What-if detection & slot extraction
// ────────────────────────────────────────────────────────────────────

const WHATIF_SLOT_PROMPT = {
  zh: `你是供应链 What-if 参数提取器。分析用户问题，判断是否是 what-if 推演场景。

What-if 类型：
1. switch-supplier — 用户想换供应商（关键词：换供应商、切换供应商、改用、换成）
2. change-lane — 用户想改运输方式（关键词：空运、改运输、换运输、改物流）
3. transfer-factory — 用户想转移生产工厂（关键词：转到…生产、转移工厂、改到…工厂）

提取以下槽位（缺失时返回null）：
- orderId: 订单编号（如 SO1001）
- partId: 零件编号（如 P1A）
- fromSupplierId: 原供应商（如 S1）
- toSupplierId: 目标供应商（如 S2）
- supplierId: 供应商（用于 change-lane）
- toLane: 目标运输方式（Ocean/Air）
- fromFactoryId: 原工厂（如 F1）
- toFactoryId: 目标工厂（如 F3）
- objective: delivery-first（默认）或 cost-first

返回 JSON: { "isWhatIf": true, "type": "switch-supplier", "slots": { ... } }
如果不是 what-if 问题: { "isWhatIf": false }`,

  en: `You are a supply chain What-if parameter extractor. Analyze the user's question.

Types:
1. switch-supplier — change supplier (keywords: switch supplier, change to, replace with)
2. change-lane — change transport mode (keywords: air freight, change shipping, expedite)
3. transfer-factory — transfer production (keywords: move to factory, transfer production)

Extract slots (null if missing):
- orderId, partId, fromSupplierId, toSupplierId, supplierId, toLane, fromFactoryId, toFactoryId, objective

Return JSON: { "isWhatIf": true, "type": "switch-supplier", "slots": { ... } }
If not what-if: { "isWhatIf": false }`,
};

interface WhatIfSlots {
  isWhatIf: boolean;
  type?: "switch-supplier" | "change-lane" | "transfer-factory";
  slots?: Record<string, string | null>;
}

async function detectWhatIf(message: string, lang: Lang): Promise<WhatIfSlots> {
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: WHATIF_SLOT_PROMPT[lang] },
      { role: "user", content: message },
    ],
    temperature: 0,
  });
  const raw = completion.choices[0]?.message?.content ?? "";
  try {
    const cleaned = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    return JSON.parse(cleaned) as WhatIfSlots;
  } catch {
    return { isWhatIf: false };
  }
}

// ────────────────────────────────────────────────────────────────────
// What-if simulation handler
// ────────────────────────────────────────────────────────────────────

async function handleWhatIf(
  message: string,
  lang: Lang,
  whatIf: WhatIfSlots,
): Promise<{ answer: string; query: string; data: unknown }> {
  const errors = ERROR_MESSAGES[lang];
  const slots = whatIf.slots ?? {};

  // Fill defaults: if orderId/partId missing, pick top-1 missing part
  if (!slots.orderId || !slots.partId) {
    try {
      const res = await fetch(`http://localhost:${PORT}/graphql`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: `{ ordersAtRisk { id status } }`,
        }),
      });
      const result = await res.json();
      const atRisk = result?.data?.ordersAtRisk;
      if (atRisk?.length > 0 && !slots.orderId) {
        slots.orderId = atRisk[0].id;
      }
    } catch { /* ignore */ }
    if (!slots.orderId) slots.orderId = "SO1001";
    if (!slots.partId) slots.partId = "P1A";
  }

  const objective = slots.objective ?? "delivery-first";

  let simEndpoint: string;
  let simBody: Record<string, unknown>;
  let queryDesc: string;

  switch (whatIf.type) {
    case "switch-supplier":
      if (!slots.toSupplierId) slots.toSupplierId = "S2"; // default alt
      simEndpoint = "/simulate/switch-supplier";
      simBody = {
        orderId: slots.orderId,
        partId: slots.partId,
        fromSupplierId: slots.fromSupplierId ?? undefined,
        toSupplierId: slots.toSupplierId,
        objective,
      };
      queryDesc = `mutation { simulateSwitchSupplier(orderId:"${slots.orderId}", partId:"${slots.partId}", toSupplierId:"${slots.toSupplierId}") { scenarios { label description eta_delta_days cost_delta_pct line_stop_risk quality_risk assumptions } recommended blastRadius { impactedOrders { id } impactedParts { id } } assumptions } }`;
      break;

    case "change-lane":
      simEndpoint = "/simulate/change-lane";
      simBody = {
        orderId: slots.orderId,
        partId: slots.partId,
        supplierId: slots.supplierId ?? slots.fromSupplierId ?? "S1",
        toLane: slots.toLane ?? "Air",
        objective,
      };
      queryDesc = `twin-sim POST ${simEndpoint}`;
      break;

    case "transfer-factory":
      if (!slots.toFactoryId) slots.toFactoryId = "F3";
      simEndpoint = "/simulate/transfer-factory";
      simBody = {
        orderId: slots.orderId,
        fromFactoryId: slots.fromFactoryId ?? undefined,
        toFactoryId: slots.toFactoryId,
        objective,
      };
      queryDesc = `twin-sim POST ${simEndpoint}`;
      break;

    default:
      return { answer: errors.parseFailed, query: "", data: null };
  }

  // Call twin-sim
  let data: unknown;
  try {
    const res = await fetch(`${TWIN_SIM_URL}${simEndpoint}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(simBody),
    });
    if (!res.ok) {
      const text = await res.text();
      return { answer: `${errors.execFailed}: twin-sim ${res.status} ${text}`, query: queryDesc, data: null };
    }
    data = await res.json();
  } catch (err) {
    return {
      answer: `${errors.execFailed}: ${err instanceof Error ? err.message : String(err)}`,
      query: queryDesc,
      data: null,
    };
  }

  // Summarize
  const summaryCompletion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SUMMARY_PROMPTS[lang] },
      {
        role: "user",
        content: `${lang === "zh" ? "用户问题" : "User question"}: ${message}\n\n${lang === "zh" ? "模拟结果" : "Simulation results"}:\n${JSON.stringify(data, null, 2)}`,
      },
    ],
    temperature: 0.3,
  });

  const answer = summaryCompletion.choices[0]?.message?.content ?? errors.noSummary;
  return { answer, query: queryDesc, data };
}

// ────────────────────────────────────────────────────────────────────
// Sourcing intent detection (Sprint 4)
// ────────────────────────────────────────────────────────────────────

const SOURCING_INTENT_PROMPT = {
  zh: `你是供应链采购寻源意图检测器。分析用户消息，判断是否属于以下采购寻源场景。

支持的寻源操作：
1. RFQ_CANDIDATES — 用户想做RFQ、寻源评分、供应商候选排序、供应商评分卡
   关键词：RFQ、做RFQ、寻源、候选、评分、排序、供应商评分卡、交期优先、成本优先、风险优先
2. SINGLE_SOURCE — 用户想查找单一来源/瓶颈件/关键件
   关键词：单一来源、瓶颈件、关键件、single source
3. CONSOLIDATE_PO — 用户想合并采购、MOQ分摊、分配方案
   关键词：MOQ、合并采购、合并下单、分摊、分配
4. SUPPLIER_CHECK — 用户想检查某供应商能否供应某零件
   关键词：能不能下单、能不能供、缺什么、资质

提取槽位（缺失时返回null）：
- partId: 零件编号（如 P1A、MCU-001）
- supplierId: 供应商编号（如 S6）
- factoryId: 工厂编号（如 F1）
- qty: 数量
- needByDate: 交期（ISO日期格式）
- objective: delivery-first / cost-first / resilience-first / balanced
- horizonDays: 合并采购时间范围天数
- policy: priority / earliest_due / risk_min
- threshold: 单一来源阈值

返回 JSON: { "isSourcing": true, "type": "RFQ_CANDIDATES", "slots": { ... } }
如果不是寻源意图: { "isSourcing": false }`,

  en: `You are a supply chain sourcing intent detector. Analyze the user's message.

Supported sourcing actions:
1. RFQ_CANDIDATES — user wants RFQ candidate scoring, supplier ranking, scorecard
   Keywords: RFQ, candidates, sourcing, ranking, scorecard, delivery-first, cost-first, resilience-first
2. SINGLE_SOURCE — user wants to find single-source / bottleneck parts
   Keywords: single source, sole source, bottleneck, critical parts
3. CONSOLIDATE_PO — user wants MOQ consolidation / allocation plan
   Keywords: MOQ, consolidate, allocation, combine orders
4. SUPPLIER_CHECK — user wants to check if a supplier can supply a part
   Keywords: can supplier, qualified, what's missing, capability

Extract slots (null if missing):
- partId, supplierId, factoryId, qty, needByDate (ISO date), objective, horizonDays, policy, threshold

Return JSON: { "isSourcing": true, "type": "RFQ_CANDIDATES", "slots": { ... } }
If not sourcing: { "isSourcing": false }`,
};

interface SourcingIntent {
  isSourcing: boolean;
  type?: "RFQ_CANDIDATES" | "SINGLE_SOURCE" | "CONSOLIDATE_PO" | "SUPPLIER_CHECK";
  slots?: Record<string, string | number | null>;
}

async function detectSourcingIntent(message: string, lang: Lang): Promise<SourcingIntent> {
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SOURCING_INTENT_PROMPT[lang] },
      { role: "user", content: message },
    ],
    temperature: 0,
  });
  const raw = completion.choices[0]?.message?.content ?? "";
  try {
    const cleaned = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    return JSON.parse(cleaned) as SourcingIntent;
  } catch {
    return { isSourcing: false };
  }
}

async function handleSourcingIntent(
  message: string,
  lang: Lang,
  intent: SourcingIntent,
): Promise<{ answer: string; query: string; data: unknown }> {
  const errors = ERROR_MESSAGES[lang];
  const slots = intent.slots ?? {};

  let endpoint: string;
  let body: Record<string, unknown>;
  let queryDesc: string;

  switch (intent.type) {
    case "RFQ_CANDIDATES":
      endpoint = "/agent/rfq-candidates";
      body = {
        partId: slots.partId ?? "P1A",
        factoryId: slots.factoryId ?? "F1",
        qty: slots.qty ? Number(slots.qty) : 1000,
        objective: slots.objective ?? "balanced",
      };
      if (slots.needByDate) body.needByDate = slots.needByDate;
      queryDesc = `rfqCandidates(partId:"${body.partId}", qty:${body.qty}, objective:"${body.objective}")`;
      break;

    case "SINGLE_SOURCE":
      endpoint = "/agent/single-source-parts";
      body = { threshold: slots.threshold ? Number(slots.threshold) : 1 };
      queryDesc = `singleSourceParts(threshold:${body.threshold})`;
      break;

    case "CONSOLIDATE_PO":
      endpoint = "/agent/consolidate-po";
      body = {
        partId: slots.partId ?? "P1A",
        horizonDays: slots.horizonDays ? Number(slots.horizonDays) : 30,
        policy: slots.policy ?? "priority",
      };
      queryDesc = `consolidatePO(partId:"${body.partId}")`;
      break;

    case "SUPPLIER_CHECK": {
      // Check if supplier can supply the part — use rfq-candidates filtered to 1 supplier
      endpoint = "/agent/rfq-candidates";
      body = {
        partId: slots.partId ?? "P1A",
        factoryId: slots.factoryId ?? "F1",
        qty: slots.qty ? Number(slots.qty) : 1000,
        objective: "balanced",
      };
      queryDesc = `rfqCandidates for supplier check ${slots.supplierId ?? "?"}`;
      break;
    }

    default:
      return { answer: errors.parseFailed, query: "", data: null };
  }

  let data: unknown;
  try {
    const res = await fetch(`${AGENT_API_URL}${endpoint}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text();
      return {
        answer: `${errors.execFailed}: agent-api ${res.status} ${text}`,
        query: queryDesc,
        data: null,
      };
    }
    data = await res.json();
  } catch (err) {
    return {
      answer: `${errors.execFailed}: ${err instanceof Error ? err.message : String(err)}`,
      query: queryDesc,
      data: null,
    };
  }

  // For SUPPLIER_CHECK, filter results to the specific supplier
  if (intent.type === "SUPPLIER_CHECK" && slots.supplierId && data && typeof data === "object") {
    const rfqData = data as { candidates?: Array<Record<string, unknown>> };
    const match = rfqData.candidates?.find(
      (c) => c.supplierId === slots.supplierId,
    );
    if (match) {
      data = { supplierCheck: match, allCandidates: rfqData.candidates?.length ?? 0 };
    } else {
      data = {
        supplierCheck: null,
        reason: `Supplier ${slots.supplierId} does not supply part ${slots.partId ?? "?"}`,
        allCandidates: rfqData.candidates?.length ?? 0,
      };
    }
  }

  // Summarize
  const summaryCompletion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SUMMARY_PROMPTS[lang] },
      {
        role: "user",
        content: `${lang === "zh" ? "用户问题" : "User question"}: ${message}\n\n${lang === "zh" ? "寻源分析结果" : "Sourcing analysis results"}:\n${JSON.stringify(data, null, 2)}`,
      },
    ],
    temperature: 0.3,
  });

  const answer = summaryCompletion.choices[0]?.message?.content ?? errors.noSummary;
  return { answer, query: queryDesc, data };
}

// ────────────────────────────────────────────────────────────────────
// Action intent detection & execution (Sprint 3)
// ────────────────────────────────────────────────────────────────────

const ACTION_INTENT_PROMPT = {
  zh: `你是供应链行动意图检测器。分析用户的消息，判断是否要求执行具体操作。

支持的操作：
1. CREATE_PO — 用户想创建采购单（关键词：创建PO、下采购单、采购、买）
2. EXPEDITE_SHIPMENT — 用户想加急发货（关键词：加急、加速、空运发货、改运输方式）

提取以下槽位（缺失时返回null）：
- partId: 零件编号（如 P1A）
- supplierId: 供应商编号（如 S2）
- qty: 数量（整数）
- orderId: 订单编号（如 SO1001）
- poId: 采购单编号（如 PO-ERP-2001）
- newMode: 运输方式（Air/Ocean）

返回 JSON: { "isAction": true, "action": "CREATE_PO", "slots": { ... } }
如果不是操作意图: { "isAction": false }`,

  en: `You are a supply chain action intent detector. Analyze the user's message.

Supported actions:
1. CREATE_PO — user wants to create a purchase order (keywords: create PO, purchase order, buy, order from)
2. EXPEDITE_SHIPMENT — user wants to expedite shipment (keywords: expedite, speed up, air freight, rush)

Extract slots (null if missing):
- partId, supplierId, qty, orderId, poId, newMode

Return JSON: { "isAction": true, "action": "CREATE_PO", "slots": { ... } }
If not an action intent: { "isAction": false }`,
};

interface ActionIntent {
  isAction: boolean;
  action?: "CREATE_PO" | "EXPEDITE_SHIPMENT";
  slots?: Record<string, string | number | null>;
}

async function detectActionIntent(message: string, lang: Lang): Promise<ActionIntent> {
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: ACTION_INTENT_PROMPT[lang] },
      { role: "user", content: message },
    ],
    temperature: 0,
  });
  const raw = completion.choices[0]?.message?.content ?? "";
  try {
    const cleaned = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    return JSON.parse(cleaned) as ActionIntent;
  } catch {
    return { isAction: false };
  }
}

async function handleActionIntent(
  message: string,
  lang: Lang,
  intent: ActionIntent,
): Promise<{ answer: string; query: string; data: unknown }> {
  const errors = ERROR_MESSAGES[lang];
  const slots = intent.slots ?? {};

  const body: Record<string, unknown> = {
    action: intent.action,
    partId: slots.partId ?? null,
    supplierId: slots.supplierId ?? null,
    qty: slots.qty ? Number(slots.qty) : null,
    orderId: slots.orderId ?? null,
    poId: slots.poId ?? null,
    newMode: slots.newMode ?? null,
    actor: "chat-user",
  };

  let data: unknown;
  try {
    const res = await fetch(`${AGENT_API_URL}/agent/execute`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text();
      return {
        answer: `${errors.execFailed}: agent-api ${res.status} ${text}`,
        query: `POST /agent/execute ${intent.action}`,
        data: null,
      };
    }
    data = await res.json();
  } catch (err) {
    return {
      answer: `${errors.execFailed}: ${err instanceof Error ? err.message : String(err)}`,
      query: `POST /agent/execute ${intent.action}`,
      data: null,
    };
  }

  // Summarize
  const summaryCompletion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SUMMARY_PROMPTS[lang] },
      {
        role: "user",
        content: `${lang === "zh" ? "用户请求" : "User request"}: ${message}\n\n${lang === "zh" ? "执行结果" : "Execution result"}:\n${JSON.stringify(data, null, 2)}`,
      },
    ],
    temperature: 0.3,
  });

  const answer = summaryCompletion.choices[0]?.message?.content ?? errors.noSummary;
  return { answer, query: `POST /agent/execute ${intent.action}`, data };
}

// ────────────────────────────────────────────────────────────────────
// Main chat handler
// ────────────────────────────────────────────────────────────────────

export async function handleChat(
  message: string,
  lang: Lang = "zh",
): Promise<{ answer: string; query: string; data: unknown }> {
  const errors = ERROR_MESSAGES[lang];

  // Step 0a: Detect sourcing intent (RFQ / single-source / MOQ consolidation)
  const sourcingIntent = await detectSourcingIntent(message, lang);
  if (sourcingIntent.isSourcing && sourcingIntent.type) {
    return handleSourcingIntent(message, lang, sourcingIntent);
  }

  // Step 0b: Detect action intent (CREATE_PO / EXPEDITE_SHIPMENT)
  const actionIntent = await detectActionIntent(message, lang);
  if (actionIntent.isAction && actionIntent.action) {
    return handleActionIntent(message, lang, actionIntent);
  }

  // Step 0c: Detect what-if intent
  const whatIf = await detectWhatIf(message, lang);
  if (whatIf.isWhatIf && whatIf.type) {
    return handleWhatIf(message, lang, whatIf);
  }

  // Step 1: Convert natural language to GraphQL query
  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SYSTEM_PROMPTS[lang] },
      { role: "user", content: message },
    ],
    temperature: 0,
  });

  const raw = completion.choices[0]?.message?.content ?? "";

  let query: string;
  let variables: Record<string, unknown> = {};
  try {
    const cleaned = raw.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
    const parsed = JSON.parse(cleaned);
    query = parsed.query ?? "";
    variables = parsed.variables ?? {};
    // GPT returned a direct answer instead of a query (vague question)
    if (!query && parsed.answer) {
      return { answer: parsed.answer, query: "", data: null };
    }
  } catch {
    return { answer: errors.parseFailed, query: raw, data: null };
  }

  if (!query.trim()) {
    return { answer: errors.parseFailed, query: raw, data: null };
  }

  // Step 2: Execute via our own GraphQL endpoint (preserves Neo4j context)
  let data: unknown;
  try {
    const res = await fetch(`http://localhost:${PORT}/graphql`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query, variables }),
    });
    const result = await res.json();
    if (result.errors && result.errors.length > 0) {
      return {
        answer: `${errors.queryError}: ${result.errors.map((e: { message: string }) => e.message).join("; ")}`,
        query,
        data: null,
      };
    }
    data = result.data;
  } catch (err) {
    return {
      answer: `${errors.execFailed}: ${err instanceof Error ? err.message : String(err)}`,
      query,
      data: null,
    };
  }

  // Step 3: Generate natural language summary
  const summaryCompletion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SUMMARY_PROMPTS[lang] },
      {
        role: "user",
        content: `${lang === "zh" ? "用户问题" : "User question"}: ${message}\n\n${lang === "zh" ? "查询结果" : "Query results"}:\n${JSON.stringify(data, null, 2)}`,
      },
    ],
    temperature: 0.3,
  });

  const answer = summaryCompletion.choices[0]?.message?.content ?? errors.noSummary;

  return { answer, query, data };
}
