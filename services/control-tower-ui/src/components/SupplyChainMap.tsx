import { useQuery } from "@apollo/client";
import { GET_SUPPLY_CHAIN } from "../graphql/queries";

export default function SupplyChainMap() {
  const { data, loading, error } = useQuery(GET_SUPPLY_CHAIN);

  if (loading) return <p className="loading">加载供应链数据中...</p>;
  if (error) return <p className="error">错误: {error.message}</p>;

  const suppliers = data?.suppliers ?? [];

  return (
    <div className="supply-chain">
      {suppliers.map(
        (s: {
          id: string;
          name: string;
          affectedBy: Array<{ id: string; type: string; severity: number }>;
          supplies: Array<{
            id: string;
            name: string;
            partType: string;
            inventoryLots: Array<{
              id: string;
              location: string;
              onHand: number;
              reserved: number;
            }>;
          }>;
        }) => (
          <div key={s.id} className="supplier-card">
            <div className="card-header">
              <strong>{s.name}</strong>
              <span className="part-id">({s.id})</span>
              {s.affectedBy.length > 0 && (
                <span className="badge badge-danger">
                  {s.affectedBy.length} 项风险
                </span>
              )}
            </div>
            <div className="parts-supplied">
              {s.supplies.map((p) => (
                <div key={p.id} className="part-row">
                  <span className="tag">{p.name}</span>
                  {p.inventoryLots.map((lot) => (
                    <span key={lot.id} className="inventory-info">
                      {lot.location}: 可用 {lot.onHand - lot.reserved} / 库存 {lot.onHand}
                    </span>
                  ))}
                </div>
              ))}
            </div>
          </div>
        )
      )}
    </div>
  );
}
