import { useQuery } from "@apollo/client";
import { GET_RISK_EVENTS } from "../graphql/queries";

export default function RiskAlerts() {
  const { data, loading, error } = useQuery(GET_RISK_EVENTS);

  if (loading) return <p className="loading">加载风险信息中...</p>;
  if (error) return <p className="error">错误: {error.message}</p>;

  const risks = data?.riskEvents ?? [];

  return (
    <div className="card-list">
      {risks.length === 0 && <p>当前无活跃风险事件。</p>}
      {risks.map(
        (r: {
          id: string;
          type: string;
          severity: number;
          date: string;
          affects: Array<{
            id: string;
            name: string;
            supplies: Array<{ id: string; name: string }>;
          }>;
        }) => (
          <div key={r.id} className={`card risk-card severity-${r.severity >= 4 ? "high" : "low"}`}>
            <div className="card-header">
              <strong>{r.type}</strong>
              <span className="badge badge-danger">严重等级 {r.severity}/5</span>
            </div>
            <p>日期: {r.date ?? "未知"}</p>
            <p>
              受影响供应商:{" "}
              {r.affects.map((s) => (
                <span key={s.id} className="tag">
                  {s.name}
                  {s.supplies.length > 0 && (
                    <> &rarr; {s.supplies.map((p) => p.name).join(", ")}</>
                  )}
                </span>
              ))}
            </p>
          </div>
        )
      )}
    </div>
  );
}
