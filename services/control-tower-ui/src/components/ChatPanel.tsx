import { useState, useRef, useEffect, ReactNode } from "react";

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  query?: string;
  data?: unknown;
}

/** Parse inline **bold** markers */
function inlineBold(text: string): ReactNode[] {
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return parts.map((p, i) =>
    p.startsWith("**") && p.endsWith("**") ? (
      <strong key={i}>{p.slice(2, -2)}</strong>
    ) : (
      p
    ),
  );
}

/** Convert markdown content (tables, headings, bold) to JSX */
function renderMarkdown(content: string): ReactNode[] {
  const lines = content.split("\n");
  const blocks: { type: "text" | "table"; lines: string[] }[] = [];
  let cur: { type: "text" | "table"; lines: string[] } = { type: "text", lines: [] };

  for (const line of lines) {
    const isTable = line.trimStart().startsWith("|");
    if (isTable && cur.type !== "table") {
      if (cur.lines.length) blocks.push(cur);
      cur = { type: "table", lines: [line] };
    } else if (!isTable && cur.type === "table") {
      if (cur.lines.length) blocks.push(cur);
      cur = { type: "text", lines: [line] };
    } else {
      cur.lines.push(line);
    }
  }
  if (cur.lines.length) blocks.push(cur);

  return blocks.map((block, bi) => {
    if (block.type === "text") {
      const text = block.lines
        .map((l) => (l.startsWith("### ") ? l.slice(4) : l.startsWith("## ") ? l.slice(3) : l))
        .join("\n");
      return <span key={bi}>{inlineBold(text)}</span>;
    }
    // Markdown table → HTML table
    const isSep = (l: string) => /^\s*\|[\s\-:|]+\|\s*$/.test(l);
    const dataLines = block.lines.filter((l) => !isSep(l));
    if (!dataLines.length) return null;
    const parseRow = (line: string) =>
      line.split("|").slice(1, -1).map((c) => c.trim());
    const headers = parseRow(dataLines[0]);
    const rows = dataLines.slice(1).map(parseRow);
    return (
      <table key={bi} className="data-table chat-data-table">
        <thead>
          <tr>{headers.map((h, hi) => <th key={hi}>{h}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((row, ri) => (
            <tr key={ri}>{row.map((c, ci) => <td key={ci}>{c}</td>)}</tr>
          ))}
        </tbody>
      </table>
    );
  });
}

const QUICK_QUESTIONS = [
  "显示所有订单",
  "哪些供应商有风险",
  "库存情况",
  "在途运输",
  "SO1001 的状态是什么",
  "BOM-1001 的组件有哪些",
];

const CHAT_API = "http://localhost:4000/chat";

export default function ChatPanel() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [expandedIdx, setExpandedIdx] = useState<number | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  async function sendMessage(text: string) {
    if (!text.trim() || loading) return;

    const userMsg: ChatMessage = { role: "user", content: text };
    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setLoading(true);

    try {
      const res = await fetch(CHAT_API, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text, lang: "zh" }),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: "请求失败" }));
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: `错误: ${err.error ?? res.statusText}` },
        ]);
        return;
      }

      const result = await res.json();
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: result.answer,
          query: result.query,
          data: result.data,
        },
      ]);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          role: "assistant",
          content: `网络错误: ${err instanceof Error ? err.message : "无法连接到服务器"}`,
        },
      ]);
    } finally {
      setLoading(false);
    }
  }

  function renderData(data: unknown) {
    if (!data || typeof data !== "object") return null;
    const entries = Object.entries(data as Record<string, unknown>);
    if (entries.length === 0) return null;

    const [, value] = entries[0];
    if (!Array.isArray(value) || value.length === 0) {
      return <pre className="chat-data-raw">{JSON.stringify(data, null, 2)}</pre>;
    }

    const rows = value as Record<string, unknown>[];
    const columns = Object.keys(rows[0]).filter(
      (k) => typeof rows[0][k] !== "object" || rows[0][k] === null,
    );

    return (
      <table className="data-table chat-data-table">
        <thead>
          <tr>
            {columns.map((col) => (
              <th key={col}>{col}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.slice(0, 20).map((row, i) => (
            <tr key={i}>
              {columns.map((col) => (
                <td key={col}>{String(row[col] ?? "—")}</td>
              ))}
            </tr>
          ))}
          {rows.length > 20 && (
            <tr>
              <td colSpan={columns.length} style={{ textAlign: "center", color: "var(--text-muted)" }}>
                ... 还有 {rows.length - 20} 条记录
              </td>
            </tr>
          )}
        </tbody>
      </table>
    );
  }

  return (
    <div className="chat-panel">
      {messages.length === 0 && (
        <div className="chat-welcome">
          <h2>对话查询</h2>
          <p>用自然语言查询供应链数据，例如：</p>
          <div className="chat-quick-buttons">
            {QUICK_QUESTIONS.map((q) => (
              <button key={q} className="chat-quick-btn" onClick={() => sendMessage(q)}>
                {q}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="chat-messages">
        {messages.map((msg, i) => (
          <div key={i} className={`chat-msg chat-msg-${msg.role}`}>
            <div className="chat-msg-label">{msg.role === "user" ? "你" : "AI 助手"}</div>
            <div className="chat-msg-content">{renderMarkdown(msg.content)}</div>
            {msg.query && (
              <div className="chat-details">
                <button
                  className="chat-toggle-btn"
                  onClick={() => {
                    const next = expandedIdx === i ? null : i;
                    setExpandedIdx(next);
                    if (next !== null) {
                      setTimeout(() => {
                        document.getElementById(`chat-detail-${i}`)?.scrollIntoView({ behavior: "smooth", block: "nearest" });
                      }, 50);
                    }
                  }}
                >
                  {expandedIdx === i ? "▾ 收起查询详情" : "▸ 查看查询详情"}
                </button>
                {expandedIdx === i && (
                  <div className="chat-detail-body" id={`chat-detail-${i}`}>
                    <div className="chat-query-section">
                      <strong>GraphQL 查询:</strong>
                      <pre className="chat-query-code">{msg.query}</pre>
                    </div>
                    {msg.data != null && (
                      <div className="chat-data-section">
                        <strong>数据:</strong>
                        {renderData(msg.data)}
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
        {loading && (
          <div className="chat-msg chat-msg-assistant">
            <div className="chat-msg-label">AI 助手</div>
            <div className="chat-msg-content chat-loading">思考中...</div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <div className="chat-input-bar">
        {messages.length > 0 && (
          <div className="chat-quick-row">
            {QUICK_QUESTIONS.map((q) => (
              <button key={q} className="chat-quick-btn chat-quick-btn-sm" onClick={() => sendMessage(q)}>
                {q}
              </button>
            ))}
          </div>
        )}
        <form
          className="chat-form"
          onSubmit={(e) => {
            e.preventDefault();
            sendMessage(input);
          }}
        >
          <input
            className="chat-input"
            type="text"
            placeholder="输入你的问题..."
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={loading}
          />
          <button className="chat-send-btn" type="submit" disabled={loading || !input.trim()}>
            发送
          </button>
        </form>
      </div>
    </div>
  );
}
