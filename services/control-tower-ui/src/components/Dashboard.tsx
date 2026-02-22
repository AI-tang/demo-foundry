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
            <h2>Orders</h2>
            <OrdersTable />
          </section>
          <section>
            <h2>Risk Alerts</h2>
            <RiskAlerts />
          </section>
          <section>
            <h2>System Status</h2>
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
