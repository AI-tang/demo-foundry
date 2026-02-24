import { useState } from "react";
import RfqCandidates from "./sourcing/RfqCandidates";
import SingleSourceRisk from "./sourcing/SingleSourceRisk";
import MoqConsolidation from "./sourcing/MoqConsolidation";

type SourcingSubTab = "rfq" | "single-source" | "moq";

const SUB_TABS: [SourcingSubTab, string][] = [
  ["rfq", "RFQ 候选评估"],
  ["single-source", "单一来源风险"],
  ["moq", "MOQ 合并"],
];

export default function SourcingPanel() {
  const [sub, setSub] = useState<SourcingSubTab>("rfq");

  return (
    <div className="sourcing-panel">
      <nav className="sourcing-sub-tabs">
        {SUB_TABS.map(([key, label]) => (
          <button
            key={key}
            className={sub === key ? "sub-tab active" : "sub-tab"}
            onClick={() => setSub(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      <div className="sourcing-content">
        {sub === "rfq" && <RfqCandidates />}
        {sub === "single-source" && <SingleSourceRisk />}
        {sub === "moq" && <MoqConsolidation />}
      </div>
    </div>
  );
}
