/**
 * sourcing.ts – GraphQL types + resolvers for Sprint 4 sourcing scenarios.
 *
 * Proxies to agent-api for RFQ candidate scoring, single-source governance,
 * and MOQ consolidation. Merged into the Apollo schema in index.ts.
 */

const AGENT_API_URL = process.env.AGENT_API_URL ?? "http://agent-api:7200";

async function callAgent(path: string, body: Record<string, unknown>) {
  const res = await fetch(`${AGENT_API_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`agent-api ${path} ${res.status}: ${text}`);
  }
  return res.json();
}

// ── GraphQL type definitions ─────────────────────────────────────

export const sourcingTypeDefs = /* GraphQL */ `
  type CandidateBreakdown {
    lead: Float!
    cost: Float!
    risk: Float!
    lane: Float!
    penalties: Float!
  }

  type RfqCandidate {
    rank: Int!
    supplierId: String!
    supplierName: String!
    totalScore: Float!
    breakdown: CandidateBreakdown!
    explanations: [String!]!
    recommendedActions: [String!]!
    hardFail: Boolean!
    hardFailReason: String
  }

  type RfqResult {
    partId: String!
    qty: Int!
    objective: String!
    candidates: [RfqCandidate!]!
  }

  type SingleSourceSupplier {
    supplierId: String!
    name: String!
    qualification: String!
    approved: Boolean!
  }

  type SingleSourcePart {
    partId: String!
    partName: String!
    supplierCount: Int!
    suppliers: [SingleSourceSupplier!]!
    riskExplanation: String!
    recommendation: String!
  }

  type SingleSourceResult {
    parts: [SingleSourcePart!]!
  }

  type AllocationItem {
    orderId: String!
    qty: Int!
    needByDate: String!
    priority: Int!
  }

  type ConsolidateResult {
    partId: String!
    totalDemand: Int!
    consolidatedQty: Int!
    supplierId: String!
    supplierName: String!
    moq: Int!
    unitPrice: Float!
    allocations: [AllocationItem!]!
    explanation: String!
  }

  type Query {
    rfqCandidates(
      partId: String!
      factoryId: String
      qty: Int
      needByDate: String
      objective: String
    ): RfqResult!

    singleSourceParts(threshold: Int): SingleSourceResult!

    consolidatePO(
      partId: String!
      horizonDays: Int
      policy: String
    ): ConsolidateResult!
  }

  type SourcingExecuteResult {
    success: Boolean!
    message: String!
    auditEventId: String
    actionRequestId: String
    details: JSON
  }

  scalar JSON

  type Mutation {
    createPOFromRfq(
      partId: String!
      supplierId: String!
      qty: Int!
      orderId: String
    ): SourcingExecuteResult!
  }
`;

// ── Resolvers ────────────────────────────────────────────────────

export const sourcingResolvers = {
  Query: {
    rfqCandidates: async (
      _: unknown,
      args: {
        partId: string;
        factoryId?: string;
        qty?: number;
        needByDate?: string;
        objective?: string;
      },
    ) => {
      const body: Record<string, unknown> = {
        partId: args.partId,
        factoryId: args.factoryId ?? "F1",
        qty: args.qty ?? 1000,
        objective: args.objective ?? "balanced",
      };
      if (args.needByDate) body.needByDate = args.needByDate;
      const data = await callAgent("/agent/rfq-candidates", body);
      return data;
    },

    singleSourceParts: async (
      _: unknown,
      args: { threshold?: number },
    ) => {
      const data = await callAgent("/agent/single-source-parts", {
        threshold: args.threshold ?? 1,
      });
      return data;
    },

    consolidatePO: async (
      _: unknown,
      args: { partId: string; horizonDays?: number; policy?: string },
    ) => {
      return callAgent("/agent/consolidate-po", {
        partId: args.partId,
        horizonDays: args.horizonDays ?? 30,
        policy: args.policy ?? "priority",
      });
    },
  },

  Mutation: {
    createPOFromRfq: async (
      _: unknown,
      args: { partId: string; supplierId: string; qty: number; orderId?: string },
    ) => {
      return callAgent("/agent/execute", {
        action: "CREATE_PO",
        partId: args.partId,
        supplierId: args.supplierId,
        qty: args.qty,
        orderId: args.orderId ?? null,
        actor: "rfq-recommendation",
      });
    },
  },

  // Map the suppliers array from agent-api (dict) to SingleSourceSupplier type
  SingleSourcePart: {
    suppliers: (parent: { suppliers: Array<Record<string, unknown>> }) => {
      return (parent.suppliers ?? []).map((s) => ({
        supplierId: s.supplierId ?? s.supplier_id ?? "",
        name: s.name ?? "",
        qualification: s.qualification ?? s.qualification_level ?? "",
        approved: s.approved ?? false,
      }));
    },
  },
};
