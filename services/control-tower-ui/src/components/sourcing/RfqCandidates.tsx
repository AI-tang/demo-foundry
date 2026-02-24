import { useState } from "react";
import { useLazyQuery } from "@apollo/client";
import { GET_RFQ_CANDIDATES } from "../../graphql/queries";

const OBJECTIVES: [string, string][] = [
  ["balanced", "均衡"],
  ["cost-first", "低成本"],
  ["delivery-first", "最快交货"],
  ["resilience-first", "低风险"],
];

export default function RfqCandidates() {
  const [partId, setPartId] = useState("");
  const [qty, setQty] = useState(1000);
  const [objective, setObjective] = useState("balanced");

  const [fetch, { data, loading, error }] = useLazyQuery(GET_RFQ_CANDIDATES);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!partId.trim()) return;
    fetch({ variables: { partId: partId.trim(), qty, objective } });
  };

  const candidates = data?.rfqCandidates?.candidates ?? [];

  return (
    <div>
      <form className="sourcing-form" onSubmit={handleSubmit}>
        <label>
          零件ID
          <input
            type="text"
            value={partId}
            onChange={(e) => setPartId(e.target.value)}
            placeholder="例如 P1A"
          />
        </label>
        <label>
          数量
          <input
            type="number"
            value={qty}
            min={1}
            onChange={(e) => setQty(Number(e.target.value))}
          />
        </label>
        <label>
          评估策略
          <select value={objective} onChange={(e) => setObjective(e.target.value)}>
            {OBJECTIVES.map(([val, label]) => (
              <option key={val} value={val}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" className="sourcing-submit" disabled={loading}>
          {loading ? "查询中…" : "查询候选"}
        </button>
      </form>

      {error && <p className="error">查询失败: {error.message}</p>}

      {candidates.length > 0 && (
        <table className="data-table">
          <thead>
            <tr>
              <th>排名</th>
              <th>供应商</th>
              <th>总分</th>
              <th>交货</th>
              <th>成本</th>
              <th>风险</th>
              <th>物流</th>
              <th>惩罚</th>
              <th>说明 / 建议</th>
            </tr>
          </thead>
          <tbody>
            {candidates.map((c: any) => (
              <tr
                key={c.supplierId}
                className={c.hardFail ? "row-hard-fail" : ""}
              >
                <td>
                  {c.rank}
                  {" "}
                  {c.hardFail ? (
                    <span className="badge badge-danger">{c.hardFailReason ?? "不合格"}</span>
                  ) : c.rank === 1 ? (
                    <span className="badge badge-ok">推荐</span>
                  ) : null}
                </td>
                <td>{c.supplierName}</td>
                <td>
                  <div className="score-bar-wrap">
                    <div
                      className="score-bar"
                      style={{ width: `${Math.round(c.totalScore)}%` }}
                    />
                    <span className="score-label">{c.totalScore.toFixed(1)}</span>
                  </div>
                </td>
                <td>{c.breakdown.lead.toFixed(1)}</td>
                <td>{c.breakdown.cost.toFixed(1)}</td>
                <td>{c.breakdown.risk.toFixed(1)}</td>
                <td>{c.breakdown.lane.toFixed(1)}</td>
                <td>{c.breakdown.penalties.toFixed(1)}</td>
                <td>
                  {c.explanations.length > 0 && (
                    <ul className="explain-list">
                      {c.explanations.map((ex: string, i: number) => (
                        <li key={i}>{ex}</li>
                      ))}
                    </ul>
                  )}
                  {c.recommendedActions.length > 0 && (
                    <div className="action-tags">
                      {c.recommendedActions.map((a: string, i: number) => (
                        <span key={i} className="tag">
                          {a}
                        </span>
                      ))}
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
