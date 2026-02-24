import { useState } from "react";
import Dashboard from "./components/Dashboard";

type Tab = "overview" | "orders" | "risks" | "bom" | "supply" | "sourcing" | "chat";

export default function App() {
  const [tab, setTab] = useState<Tab>("overview");

  return (
    <div className="app">
      <header className="app-header">
        <h1>Control Tower</h1>
        <span className="subtitle">供应链可视化平台</span>
      </header>
      <nav className="tab-bar">
        {(
          [
            ["overview", "总览"],
            ["orders", "订单"],
            ["risks", "风险预警"],
            ["bom", "物料清单"],
            ["supply", "供应链"],
            ["sourcing", "采购寻源"],
            ["chat", "对话查询"],
          ] as [Tab, string][]
        ).map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? "tab active" : "tab"}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      <main className="content">
        <Dashboard tab={tab} />
      </main>
    </div>
  );
}
