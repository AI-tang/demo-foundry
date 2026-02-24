import { ApolloServer } from "@apollo/server";
import { expressMiddleware } from "@apollo/server/express4";
import { Neo4jGraphQL } from "@neo4j/graphql";
import { mergeSchemas } from "@graphql-tools/schema";
import express from "express";
import cors from "cors";
import driver from "./neo4j.js";
import { typeDefs } from "./schema.js";
import { simulationTypeDefs, simulationResolvers } from "./simulation.js";
import { sourcingTypeDefs, sourcingResolvers } from "./sourcing.js";
import { handleChat, type Lang, type HistoryMessage } from "./chat.js";

const PORT = parseInt(process.env.PORT ?? "4000", 10);

async function main() {
  // 1. Neo4j-backed schema (auto-generated CRUD + @cypher queries)
  const neoSchema = new Neo4jGraphQL({ typeDefs, driver });
  const neo4jSchema = await neoSchema.getSchema();

  // 2. Simulation schema (custom resolvers calling twin-sim service)
  const { makeExecutableSchema } = await import("@graphql-tools/schema");
  const simSchema = makeExecutableSchema({
    typeDefs: simulationTypeDefs,
    resolvers: simulationResolvers,
  });

  // 3. Sourcing schema (RFQ candidates, single-source, MOQ consolidation)
  const srcSchema = makeExecutableSchema({
    typeDefs: sourcingTypeDefs,
    resolvers: sourcingResolvers,
  });

  // 4. Merge all into a single Apollo schema
  const schema = mergeSchemas({ schemas: [neo4jSchema, simSchema, srcSchema] });

  const server = new ApolloServer({ schema });
  await server.start();

  const app = express();
  app.use(cors());
  app.use(express.json());

  app.use("/graphql", expressMiddleware(server));

  app.post("/chat", async (req, res) => {
    const { message, lang, history } = req.body;
    if (!message || typeof message !== "string") {
      res.status(400).json({ error: "message is required" });
      return;
    }
    const resolvedLang: Lang = lang === "en" ? "en" : "zh";
    const resolvedHistory: HistoryMessage[] = Array.isArray(history) ? history : [];
    try {
      const result = await handleChat(message, resolvedLang, resolvedHistory);
      res.json(result);
    } catch (err) {
      console.error("Chat error:", err);
      res.status(500).json({
        error: err instanceof Error ? err.message : "Internal server error",
      });
    }
  });

  app.listen(PORT, () => {
    console.log(`GraphQL API ready at http://localhost:${PORT}/graphql`);
    console.log(`Chat endpoint ready at http://localhost:${PORT}/chat`);
  });
}

main().catch((err) => {
  console.error("Failed to start GraphQL server:", err);
  process.exit(1);
});
