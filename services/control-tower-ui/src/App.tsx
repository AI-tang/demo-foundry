import { useState } from "react";
import Dashboard from "./components/Dashboard";

type Tab = "overview" | "orders" | "risks" | "bom" | "supply" | "chat";

export default function App() {
  const [tab, setTab] = useState<Tab>("overview");

  return (
    <div className="app">
      <header className="app-header">
        <h1>Control Tower</h1>
        <span className="subtitle">Demo Foundry &mdash; Supply Chain Visibility</span>
      </header>
      <nav className="tab-bar">
        {(
          [
            ["overview", "Overview"],
            ["orders", "Orders"],
            ["risks", "Risks"],
            ["bom", "BOM"],
            ["supply", "Supply Chain"],
            ["chat", "Chat / 对话查询"],
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
