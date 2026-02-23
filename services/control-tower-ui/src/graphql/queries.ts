import { gql } from "@apollo/client";

export const GET_ORDERS = gql`
  query GetOrders {
    orders {
      id
      status
      produces {
        id
        name
      }
      statuses {
        system
        objectId
        status
        updatedAt
      }
      requires {
        id
        name
        partType
      }
    }
  }
`;

export const GET_RISK_EVENTS = gql`
  query GetRiskEvents {
    riskEvents {
      id
      type
      severity
      date
      affects {
        id
        name
        supplies {
          id
          name
        }
      }
    }
  }
`;

export const GET_BOM = gql`
  query GetBOM {
    products {
      id
      name
      components {
        id
        name
        partType
        suppliedBy {
          id
          name
        }
        components {
          id
          name
          partType
          suppliedBy {
            id
            name
          }
        }
      }
    }
  }
`;

export const GET_SUPPLY_CHAIN = gql`
  query GetSupplyChain {
    suppliers {
      id
      name
      supplies {
        id
        name
        partType
        inventoryLots {
          id
          location
          onHand
          reserved
        }
      }
      affectedBy {
        id
        type
        severity
      }
    }
  }
`;
