import { useQuery } from "@apollo/client";
import { GET_ORDERS } from "../graphql/queries";

export default function SystemStatusGrid() {
  const { data, loading, error } = useQuery(GET_ORDERS);

  if (loading) return <p className="loading">加载系统状态中...</p>;
  if (error) return <p className="error">错误: {error.message}</p>;

  const orders = data?.orders ?? [];

  return (
    <div className="status-grid">
      {orders.map(
        (o: {
          id: string;
          status: string;
          statuses: Array<{ system: string; status: string; updatedAt: string }>;
        }) => (
          <div key={o.id} className="status-card">
            <h4>
              {o.id}{" "}
              <span className={`badge ${o.status === "AtRisk" ? "badge-danger" : "badge-ok"}`}>
                {o.status === "AtRisk" ? "有风险" : o.status === "OnTrack" ? "正常" : o.status}
              </span>
            </h4>
            <div className="system-pills">
              {(o.statuses ?? []).map((s) => (
                <div key={s.system} className="system-pill">
                  <span className="system-name">{s.system}</span>
                  <span className="system-status">{s.status}</span>
                </div>
              ))}
            </div>
          </div>
        )
      )}
    </div>
  );
}
