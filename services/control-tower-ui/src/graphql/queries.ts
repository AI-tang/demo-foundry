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

export const GET_RFQ_CANDIDATES = gql`
  query GetRfqCandidates($partId: String!, $qty: Int, $objective: String) {
    rfqCandidates(partId: $partId, qty: $qty, objective: $objective) {
      partId
      qty
      objective
      candidates {
        rank
        supplierId
        supplierName
        totalScore
        breakdown {
          lead
          cost
          risk
          lane
          penalties
        }
        explanations
        recommendedActions
        hardFail
        hardFailReason
      }
    }
  }
`;

export const GET_SINGLE_SOURCE_PARTS = gql`
  query GetSingleSourceParts($threshold: Int) {
    singleSourceParts(threshold: $threshold) {
      parts {
        partId
        partName
        supplierCount
        riskExplanation
        recommendation
        suppliers {
          supplierId
          name
          qualification
          approved
        }
      }
    }
  }
`;

export const GET_CONSOLIDATE_PO = gql`
  query GetConsolidatePO($partId: String!, $horizonDays: Int, $policy: String) {
    consolidatePO(partId: $partId, horizonDays: $horizonDays, policy: $policy) {
      partId
      totalDemand
      consolidatedQty
      supplierId
      supplierName
      moq
      unitPrice
      explanation
      allocations {
        orderId
        qty
        needByDate
        priority
      }
    }
  }
`;
