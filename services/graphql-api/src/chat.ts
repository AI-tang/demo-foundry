import OpenAI from "openai";

const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const PORT = parseInt(process.env.PORT ?? "4000", 10);

const SCHEMA_DESCRIPTION = `Available GraphQL Schema:

Types:
- Factory: id, name; relations: produces -> Product, canBackupWith -> Factory
- Supplier: id, name; relations: supplies -> Part (priority, leadTimeDays), alternativeTo -> Supplier, affectedBy <- RiskEvent
- Part: id, name, partType; relations: components -> Part, suppliedBy <- Supplier, inventoryLots <- InventoryLot, deliveredBy <- Shipment
- Product: id, name; relations: components -> Part, producedBy <- Factory, orders <- Order
- Order: id, status; relations: produces -> Product, requires -> Part, statuses -> SystemRecord
- SystemRecord: system, objectType, objectId, status, updatedAt
- RiskEvent: id, type, severity, date; relations: affects -> Supplier
- Shipment: id, mode, status, eta; relations: delivers -> Part
- InventoryLot: id, location, onHand, reserved; relations: stores -> Part
- DefectEvent: id, description, severity, date; relations: affectsPart <- Part (HAS_DEFECT)
- ECO: id, description, status, date; relations: affectedParts -> Part (ECO_AFFECTS), replacementPart -> Part (ECO_REPLACES_WITH)

Custom Analysis Queries (场景分析):
- ordersAtRisk: 返回所有有风险的订单 / Returns all at-risk orders
- missingParts: 返回缺料零件 / Returns parts with zero available inventory
- lineStopForecast: 预测可能导致停线的订单 / Predicts orders that may cause line stops
- traceQuality(defectId: String!): 根据缺陷ID追溯影响 / Trace impact by defect ID
- ecoImpact(ecoId: String!): 根据ECO编号查影响范围 / Check impact scope by ECO ID
- reconcile: 返回跨系统状态不一致的订单 / Returns orders with cross-system status conflicts

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
   Query: { inventoryLots { id location onHand reserved stores { id name } } }

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

IMPORTANT: For custom @cypher queries (ordersAtRisk, missingParts, lineStopForecast, traceQuality, ecoImpact, reconcile), ONLY request scalar fields returned by the Cypher RETURN clause. Do NOT request nested relationship fields — they will fail.

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
  zh: "你是供应链数据分析助手。根据用户的问题和查询结果，用中文生成简洁的自然语言摘要。直接回答问题，不要提及 GraphQL。",
  en: "You are a supply chain data analysis assistant. Based on the user's question and query results, generate a concise natural language summary in English. Answer the question directly without mentioning GraphQL.",
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

export async function handleChat(
  message: string,
  lang: Lang = "zh",
): Promise<{ answer: string; query: string; data: unknown }> {
  const errors = ERROR_MESSAGES[lang];

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
