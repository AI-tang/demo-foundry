import { ApolloClient, InMemoryCache, HttpLink } from "@apollo/client";

const GRAPHQL_URI =
  typeof window !== "undefined" && window.location.hostname !== "localhost"
    ? "/graphql"
    : "http://localhost:4000/graphql";

const client = new ApolloClient({
  link: new HttpLink({ uri: GRAPHQL_URI }),
  cache: new InMemoryCache(),
});

export default client;
