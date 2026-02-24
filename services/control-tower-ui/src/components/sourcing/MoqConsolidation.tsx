import { useState } from "react";
import { useLazyQuery } from "@apollo/client";
import { GET_CONSOLIDATE_PO } from "../../graphql/queries";

const POLICIES: [string, string][] = [
  ["priority", "按优先级"],
  ["earliest_due", "先到期优先"],
  ["risk_min", "风险最小"],
];

export default function MoqConsolidation() {
  const [partId, setPartId] = useState("");
  const [horizonDays, setHorizonDays] = useState(30);
  const [policy, setPolicy] = useState("priority");

  const [fetch, { data, loading, error }] = useLazyQuery(GET_CONSOLIDATE_PO);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!partId.trim()) return;
    fetch({ variables: { partId: partId.trim(), horizonDays, policy } });
  };

  const result = data?.consolidatePO;

  return (
    <div>
      <form className="sourcing-form" onSubmit={handleSubmit}>
        <label>
          零件ID
          <input
            type="text"
            value={partId}
            onChange={(e) => setPartId(e.target.value)}
            placeholder="例如 MCU-001"
          />
        </label>
        <label>
          合并周期(天)
          <input
            type="number"
            value={horizonDays}
            min={1}
            onChange={(e) => setHorizonDays(Number(e.target.value))}
          />
        </label>
        <label>
          分配策略
          <select value={policy} onChange={(e) => setPolicy(e.target.value)}>
            {POLICIES.map(([val, label]) => (
              <option key={val} value={val}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <button type="submit" className="sourcing-submit" disabled={loading}>
          {loading ? "计算中…" : "计算合并"}
        </button>
      </form>

      {error && <p className="error">查询失败: {error.message}</p>}

      {result && (
        <>
          <div className="consolidation-summary">
            <div className="summary-item">
              <span className="summary-label">总需求量</span>
              <span className="summary-value">{result.totalDemand}</span>
            </div>
            <div className="summary-item">
              <span className="summary-label">合并采购量</span>
              <span className="summary-value">{result.consolidatedQty}</span>
            </div>
            <div className="summary-item">
              <span className="summary-label">MOQ</span>
              <span className="summary-value">{result.moq}</span>
            </div>
            <div className="summary-item">
              <span className="summary-label">单价</span>
              <span className="summary-value">¥{result.unitPrice.toFixed(2)}</span>
            </div>
            <div className="summary-item">
              <span className="summary-label">供应商</span>
              <span className="summary-value">{result.supplierName}</span>
            </div>
          </div>

          <div className="explanation-box">{result.explanation}</div>

          {result.allocations.length > 0 && (
            <table className="data-table">
              <thead>
                <tr>
                  <th>订单号</th>
                  <th>数量</th>
                  <th>交期</th>
                  <th>优先级</th>
                </tr>
              </thead>
              <tbody>
                {result.allocations.map((a: any) => (
                  <tr key={a.orderId}>
                    <td>{a.orderId}</td>
                    <td>{a.qty}</td>
                    <td>{a.needByDate}</td>
                    <td>
                      <span className="badge badge-ok">P{a.priority}</span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </div>
  );
}
