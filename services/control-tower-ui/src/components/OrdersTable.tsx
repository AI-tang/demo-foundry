import { useQuery } from "@apollo/client";
import { GET_ORDERS } from "../graphql/queries";

export default function OrdersTable() {
  const { data, loading, error } = useQuery(GET_ORDERS);

  if (loading) return <p className="loading">加载订单中...</p>;
  if (error) return <p className="error">错误: {error.message}</p>;

  const orders = data?.orders ?? [];

  return (
    <table className="data-table">
      <thead>
        <tr>
          <th>订单号</th>
          <th>状态</th>
          <th>产品</th>
          <th>所需零件</th>
          <th>CRM</th>
          <th>SAP/ERP</th>
          <th>MES</th>
        </tr>
      </thead>
      <tbody>
        {orders.map((o: Record<string, unknown>) => {
          const statuses = (o.statuses as Array<{ system: string; status: string }>) ?? [];
          const bySystem = (sys: string) =>
            statuses.find((s) => s.system === sys)?.status ?? "—";
          return (
            <tr key={o.id as string}>
              <td>{o.id as string}</td>
              <td>
                <span className={`badge ${(o.status as string) === "AtRisk" ? "badge-danger" : "badge-ok"}`}>
                  {(o.status as string) === "AtRisk" ? "有风险" : (o.status as string) === "OnTrack" ? "正常" : (o.status as string)}
                </span>
              </td>
              <td>
                {((o.produces as Array<{ name: string }>) ?? []).map((p) => p.name).join(", ") || "—"}
              </td>
              <td>
                {((o.requires as Array<{ name: string }>) ?? []).map((p) => p.name).join(", ") || "—"}
              </td>
              <td>{bySystem("CRM")}</td>
              <td>{bySystem("SAP")}</td>
              <td>{bySystem("MES")}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
