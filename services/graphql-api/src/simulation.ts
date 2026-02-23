/**
 * simulation.ts – GraphQL types + resolvers for What-if Twin-Sim & Blast Radius.
 *
 * These types are NOT backed by Neo4j nodes, so we define them in a separate
 * executable schema and merge with the Neo4jGraphQL schema in index.ts.
 */

import driver from "./neo4j.js";

const TWIN_SIM_URL = process.env.TWIN_SIM_URL ?? "http://twin-sim:7100";
const AGENT_API_URL = process.env.AGENT_API_URL ?? "http://agent-api:7200";

// ── Extra typeDefs (merged into the Apollo schema) ──────────────────

export const simulationTypeDefs = /* GraphQL */ `
  type SimScenario {
    label: String!
    description: String!
    eta_delta_days: Int!
    cost_delta_pct: Float!
    line_stop_risk: Float!
    quality_risk: Float!
    assumptions: [String!]!
  }

  type BlastRadiusItem {
    id: String!
    name: String!
    type: String!
  }

  type BlastRadiusPath {
    from: String!
    relation: String!
    to: String!
  }

  type BlastRadius {
    impactedOrders:    [BlastRadiusItem!]!
    impactedParts:     [BlastRadiusItem!]!
    impactedFactories: [BlastRadiusItem!]!
    paths:             [BlastRadiusPath!]!
  }

  type SimulationResult {
    scenarios:    [SimScenario!]!
    recommended:  String!
    blastRadius:  BlastRadius!
    assumptions:  [String!]!
  }

  type Query {
    blastRadius(orderId: String, supplierId: String, partId: String): BlastRadius!
  }

  type ExecuteResult {
    success: Boolean!
    message: String!
    auditEventId: String
    actionRequestId: String
    details: JSON
  }

  scalar JSON

  type Mutation {
    simulateSwitchSupplier(
      orderId: String!
      partId: String!
      toSupplierId: String!
      objective: String
      constraints: String
    ): SimulationResult!

    createPurchaseOrderRecommendation(
      partId: String!
      supplierId: String!
      qty: Int!
      orderId: String
    ): ExecuteResult!

    expediteShipment(
      poId: String!
      newMode: String
    ): ExecuteResult!
  }
`;

// ── Resolvers ───────────────────────────────────────────────────────

async function callAgentApi(path: string, body: Record<string, unknown>) {
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

async function callTwinSim(path: string, body: Record<string, unknown>) {
  const res = await fetch(`${TWIN_SIM_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`twin-sim ${path} ${res.status}: ${text}`);
  }
  return res.json();
}

function mapBlastPaths(raw: { from_node?: string; from?: string; relation: string; to_node?: string; to?: string }[]) {
  return (raw ?? []).map((p) => ({
    from: p.from ?? p.from_node ?? "",
    relation: p.relation,
    to: p.to ?? p.to_node ?? "",
  }));
}

export const simulationResolvers = {
  Query: {
    blastRadius: async (
      _: unknown,
      args: { orderId?: string; supplierId?: string; partId?: string },
    ) => {
      const params = new URLSearchParams();
      if (args.orderId) params.set("orderId", args.orderId);
      if (args.supplierId) params.set("supplierId", args.supplierId);
      if (args.partId) params.set("partId", args.partId);

      const res = await fetch(`${TWIN_SIM_URL}/blast-radius?${params}`);
      if (!res.ok) {
        const text = await res.text();
        throw new Error(`twin-sim blast-radius ${res.status}: ${text}`);
      }
      const data = await res.json();
      return { ...data, paths: mapBlastPaths(data.paths) };
    },
  },

  Mutation: {
    simulateSwitchSupplier: async (
      _: unknown,
      args: {
        orderId: string;
        partId: string;
        toSupplierId: string;
        objective?: string;
        constraints?: string;
      },
    ) => {
      const body: Record<string, unknown> = {
        orderId: args.orderId,
        partId: args.partId,
        toSupplierId: args.toSupplierId,
        objective: args.objective ?? "delivery-first",
        constraints: args.constraints ? JSON.parse(args.constraints) : {},
      };
      const data = await callTwinSim("/simulate/switch-supplier", body);
      return {
        ...data,
        blastRadius: { ...data.blastRadius, paths: mapBlastPaths(data.blastRadius?.paths) },
      };
    },

    createPurchaseOrderRecommendation: async (
      _: unknown,
      args: { partId: string; supplierId: string; qty: number; orderId?: string },
    ) => {
      return callAgentApi("/agent/execute", {
        action: "CREATE_PO",
        partId: args.partId,
        supplierId: args.supplierId,
        qty: args.qty,
        orderId: args.orderId ?? null,
        actor: "graphql-mutation",
      });
    },

    expediteShipment: async (
      _: unknown,
      args: { poId: string; newMode?: string },
    ) => {
      return callAgentApi("/agent/execute", {
        action: "EXPEDITE_SHIPMENT",
        poId: args.poId,
        newMode: args.newMode ?? "Air",
        actor: "graphql-mutation",
      });
    },
  },
};
