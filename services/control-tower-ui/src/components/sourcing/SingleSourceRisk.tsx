import { useState } from "react";
import { useQuery } from "@apollo/client";
import { GET_SINGLE_SOURCE_PARTS } from "../../graphql/queries";

export default function SingleSourceRisk() {
  const { data, loading, error } = useQuery(GET_SINGLE_SOURCE_PARTS, {
    variables: { threshold: 2 },
  });
  const [expanded, setExpanded] = useState<string | null>(null);

  if (loading) return <p className="loading">正在加载单一来源风险数据…</p>;
  if (error) return <p className="error">加载失败: {error.message}</p>;

  const parts = data?.singleSourceParts?.parts ?? [];

  return (
    <div className="card-list">
      {parts.length === 0 && <p className="loading">暂无单一来源风险零件</p>}
      {parts.map((p: any) => {
        const severity = p.supplierCount <= 1 ? "critical" : "moderate";
        const isOpen = expanded === p.partId;
        return (
          <div
            key={p.partId}
            className={`card ss-card ss-${severity}`}
            onClick={() => setExpanded(isOpen ? null : p.partId)}
          >
            <div className="card-header">
              <strong>{p.partName}</strong>
              <span className="part-id">{p.partId}</span>
              <span className={`badge ${severity === "critical" ? "badge-danger" : "badge-warning"}`}>
                {p.supplierCount} 家供应商
              </span>
            </div>
            <p className="ss-risk-text">{p.riskExplanation}</p>
            <p className="ss-recommendation">{p.recommendation}</p>

            {isOpen && p.suppliers.length > 0 && (
              <table className="data-table ss-supplier-table" onClick={(e) => e.stopPropagation()}>
                <thead>
                  <tr>
                    <th>供应商ID</th>
                    <th>名称</th>
                    <th>资质等级</th>
                    <th>认证状态</th>
                  </tr>
                </thead>
                <tbody>
                  {p.suppliers.map((s: any) => (
                    <tr key={s.supplierId}>
                      <td>{s.supplierId}</td>
                      <td>{s.name}</td>
                      <td>{s.qualification}</td>
                      <td>
                        <span className={`badge ${s.approved ? "badge-ok" : "badge-danger"}`}>
                          {s.approved ? "已认证" : "未认证"}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        );
      })}
    </div>
  );
}
