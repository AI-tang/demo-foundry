import OrdersTable from "./OrdersTable";
import RiskAlerts from "./RiskAlerts";
import BOMTree from "./BOMTree";
import SupplyChainMap from "./SupplyChainMap";
import SystemStatusGrid from "./SystemStatusGrid";
import ChatPanel from "./ChatPanel";

interface Props {
  tab: "overview" | "orders" | "risks" | "bom" | "supply" | "chat";
}

export default function Dashboard({ tab }: Props) {
  switch (tab) {
    case "overview":
      return (
        <div className="overview-grid">
          <section>
            <h2>订单</h2>
            <OrdersTable />
          </section>
          <section>
            <h2>风险预警</h2>
            <RiskAlerts />
          </section>
          <section>
            <h2>系统状态</h2>
            <SystemStatusGrid />
          </section>
        </div>
      );
    case "orders":
      return <OrdersTable />;
    case "risks":
      return <RiskAlerts />;
    case "bom":
      return <BOMTree />;
    case "supply":
      return <SupplyChainMap />;
    case "chat":
      return <ChatPanel />;
  }
}
