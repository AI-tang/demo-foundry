import { useState, useRef, useEffect } from "react";

type Lang = "zh" | "en";

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
  query?: string;
  data?: unknown;
}

const i18n = {
  zh: {
    title: "对话查询",
    subtitle: "用自然语言查询供应链数据，例如：",
    placeholder: "输入你的问题...",
    send: "发送",
    you: "你",
    assistant: "AI 助手",
    thinking: "思考中...",
    showDetails: "查看查询详情",
    hideDetails: "收起查询详情",
    graphqlQuery: "GraphQL 查询:",
    data: "数据:",
    moreRows: (n: number) => `... 还有 ${n} 条记录`,
    errorPrefix: "错误",
    networkError: "网络错误",
    fetchFailed: "请求失败",
    cannotConnect: "无法连接到服务器",
    quickQuestions: [
      "显示所有订单",
      "哪些供应商有风险",
      "库存情况",
      "在途运输",
      "SO1001 的状态是什么",
      "BOM-1001 的组件有哪些",
    ],
  },
  en: {
    title: "Chat Query",
    subtitle: "Query supply chain data using natural language, e.g.:",
    placeholder: "Type your question...",
    send: "Send",
    you: "You",
    assistant: "AI Assistant",
    thinking: "Thinking...",
    showDetails: "Show query details",
    hideDetails: "Hide query details",
    graphqlQuery: "GraphQL Query:",
    data: "Data:",
    moreRows: (n: number) => `... ${n} more rows`,
    errorPrefix: "Error",
    networkError: "Network error",
    fetchFailed: "Request failed",
    cannotConnect: "Cannot connect to server",
    quickQuestions: [
      "Show all orders",
      "Which suppliers have risks",
      "Inventory status",
      "In-transit shipments",
      "What is the status of SO1001",
      "What are the components of BOM-1001",
    ],
  },
};

const CHAT_API = "http://localhost:4000/chat";

export default function ChatPanel() {
  const [lang, setLang] = useState<Lang>("zh");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [expandedIdx, setExpandedIdx] = useState<number | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  const t = i18n[lang];

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
        body: JSON.stringify({ message: text, lang }),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({ error: t.fetchFailed }));
        setMessages((prev) => [
          ...prev,
          { role: "assistant", content: `${t.errorPrefix}: ${err.error ?? res.statusText}` },
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
          content: `${t.networkError}: ${err instanceof Error ? err.message : t.cannotConnect}`,
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
                {t.moreRows(rows.length - 20)}
              </td>
            </tr>
          )}
        </tbody>
      </table>
    );
  }

  return (
    <div className="chat-panel">
      <div className="chat-lang-bar">
        <button
          className={`chat-lang-btn ${lang === "zh" ? "active" : ""}`}
          onClick={() => setLang("zh")}
        >
          中文
        </button>
        <button
          className={`chat-lang-btn ${lang === "en" ? "active" : ""}`}
          onClick={() => setLang("en")}
        >
          EN
        </button>
      </div>

      {messages.length === 0 && (
        <div className="chat-welcome">
          <h2>{t.title}</h2>
          <p>{t.subtitle}</p>
          <div className="chat-quick-buttons">
            {t.quickQuestions.map((q) => (
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
            <div className="chat-msg-label">{msg.role === "user" ? t.you : t.assistant}</div>
            <div className="chat-msg-content">{msg.content}</div>
            {msg.query && (
              <div className="chat-details">
                <button
                  className="chat-toggle-btn"
                  onClick={() => setExpandedIdx(expandedIdx === i ? null : i)}
                >
                  {expandedIdx === i ? t.hideDetails : t.showDetails}
                </button>
                {expandedIdx === i && (
                  <div className="chat-detail-body">
                    <div className="chat-query-section">
                      <strong>{t.graphqlQuery}</strong>
                      <pre className="chat-query-code">{msg.query}</pre>
                    </div>
                    {msg.data && (
                      <div className="chat-data-section">
                        <strong>{t.data}</strong>
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
            <div className="chat-msg-label">{t.assistant}</div>
            <div className="chat-msg-content chat-loading">{t.thinking}</div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      <div className="chat-input-bar">
        {messages.length > 0 && (
          <div className="chat-quick-row">
            {t.quickQuestions.map((q) => (
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
            placeholder={t.placeholder}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            disabled={loading}
          />
          <button className="chat-send-btn" type="submit" disabled={loading || !input.trim()}>
            {t.send}
          </button>
        </form>
      </div>
    </div>
  );
}
