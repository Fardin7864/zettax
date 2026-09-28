"use client";
import { useEffect, useRef, useState } from "react";
type Row = Record<string, unknown>;
type Request = (
  path: string,
  method?: string,
  body?: unknown,
) => Promise<Row | Row[]>;
const text = (value: unknown) => (value == null ? "—" : String(value));
export function PredictionAdmin({ request }: { request: Request }) {
  const [view, setView] = useState("questions"),
    [rows, setRows] = useState<Row[]>([]),
    [cursor, setCursor] = useState<string | null>(null),
    [status, setStatus] = useState(""),
    [search, setSearch] = useState("");
  const [selected, setSelected] = useState<Row | null>(null),
    [positions, setPositions] = useState<Row[]>([]),
    [positionCursor, setPositionCursor] = useState<string | null>(null);
  const [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false),
    [create, setCreate] = useState(false);
  const requestRef = useRef(request);
  requestRef.current = request;
  const loadRef = useRef<(more?: boolean) => Promise<void>>(async () => {});
  const version = useRef(0);
  async function load(more = false) {
    const revision = ++version.current;
    const query = new URLSearchParams({
      ...(more && cursor ? { cursor } : {}),
      ...(status && view === "questions" ? { status } : {}),
      ...(search && view === "questions" ? { search } : {}),
    });
    try {
      const data = (await requestRef.current(
        `/prediction/admin/${view}?${query}`,
      )) as Row;
      if (revision !== version.current) return;
      setRows((old) =>
        more
          ? [
              ...old,
              ...(data.items as Row[]).filter(
                (r) => !old.some((p) => p.id === r.id),
              ),
            ]
          : (data.items as Row[]),
      );
      setCursor(data.nextCursor as string | null);
    } catch (e) {
      setMessage((e as Error).message);
    }
  }
  loadRef.current = load;
  useEffect(() => {
    const debounce = setTimeout(() => void loadRef.current(), 250);
    return () => clearTimeout(debounce);
  }, [view, search, status]);
  useEffect(() => {
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") void loadRef.current();
    }, 10000);
    return () => clearInterval(timer);
  }, []);
  async function action(path: string, body?: unknown) {
    if (busy) return;
    setBusy(true);
    setMessage("");
    try {
      await requestRef.current(path, "POST", body ?? {});
      setMessage("Action completed and audited.");
      await load();
      if (selected)
        setSelected(
          (await requestRef.current(
            `/prediction/questions/${selected.id}`,
          )) as Row,
        );
    } catch (e) {
      setMessage((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function open(row: Row) {
    setSelected(row);
    setPositions([]);
    setPositionCursor(null);
    try {
      const data = (await requestRef.current(
        `/prediction/admin/questions/${row.id}/positions`,
      )) as Row;
      setPositions(data.items as Row[]);
      setPositionCursor(data.nextCursor as string | null);
    } catch (e) {
      setMessage((e as Error).message);
    }
  }
  return (
    <section>
      <div className="toolbar">
        <button
          onClick={() => {
            setView("questions");
            setCursor(null);
          }}
        >
          Questions
        </button>
        <button
          onClick={() => {
            setView("reports");
            setCursor(null);
          }}
        >
          Reports
        </button>
        <button onClick={() => setCreate(!create)}>
          Create platform question
        </button>
        <button onClick={() => void load()}>Refresh predictions</button>
      </div>
      <p>
        Demo USD participation. Cancellation fully refunds all pending stakes
        atomically. Actions require trading configuration permission and are
        audited.
      </p>
      {message && <p role="status">{message}</p>}
      {view === "questions" && (
        <div className="toolbar">
          <input
            aria-label="Search prediction markets"
            placeholder="Search market…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select
            aria-label="Prediction status"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
          >
            <option value="">All states</option>
            <option value="OPEN">Open</option>
            <option value="CLOSED">Awaiting result</option>
            <option value="SETTLED">Resolved</option>
            <option value="CANCELLED">Refunded</option>
          </select>
        </div>
      )}
      {create && (
        <form
          className="card"
          onSubmit={(e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            void action("/prediction/platform/questions", {
              instrumentId: f.get("asset"),
              condition: f.get("condition"),
              targetPrice: f.get("price"),
              expiresAt: new Date(String(f.get("expiry"))).toISOString(),
            });
          }}
        >
          <h2>Create objective crypto question</h2>
          <label>
            Market slug
            <input
              name="asset"
              placeholder="btc-usd"
              required
              pattern="[a-z0-9-]{3,80}"
            />
          </label>
          <label>
            Condition
            <select name="condition">
              <option>ABOVE</option>
              <option>BELOW</option>
            </select>
          </label>
          <label>
            Target USD
            <input
              name="price"
              required
              type="number"
              min="0.000000000001"
              step="any"
            />
          </label>
          <label>
            Local expiry (10 minutes–30 days)
            <input name="expiry" type="datetime-local" required />
          </label>
          <button disabled={busy}>Publish immutable question</button>
        </form>
      )}
      <div style={{ overflowX: "auto" }}>
        <table>
          <thead>
            <tr>
              {(view === "questions"
                ? [
                    "Market",
                    "Question",
                    "Creator",
                    "Status",
                    "Participants",
                    "Demo pool",
                    "Expiry",
                    "Actions",
                  ]
                : [
                    "Prediction",
                    "Reason",
                    "Reporter",
                    "Status",
                    "Created",
                    "Actions",
                  ]
              ).map((h) => (
                <th key={h}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) =>
              view === "questions" ? (
                <tr key={text(row.id)}>
                  <td>{text(row.symbol)}</td>
                  <td>
                    {text(row.condition)} ${text(row.targetPrice)}
                  </td>
                  <td>{text(row.creator)}</td>
                  <td>
                    {text(row.displayStatus)} {text(row.outcome)}
                  </td>
                  <td>{text(row.participantCount)}</td>
                  <td>
                    $
                    {(Number(row.yesDemoPool) + Number(row.noDemoPool)).toFixed(
                      2,
                    )}
                  </td>
                  <td>{new Date(text(row.expiresAt)).toLocaleString()}</td>
                  <td>
                    <button onClick={() => void open(row)}>
                      Details & actions
                    </button>
                  </td>
                </tr>
              ) : (
                <tr key={text(row.id)}>
                  <td>{text((row.question as Row)?.symbol)}</td>
                  <td>{text(row.reason)}</td>
                  <td>{text(row.reporterId)}</td>
                  <td>{text(row.status)}</td>
                  <td>{new Date(text(row.createdAt)).toLocaleString()}</td>
                  <td>
                    {row.status === "OPEN" && (
                      <button
                        disabled={busy}
                        onClick={() => {
                          const reason = window.prompt(
                            "Resolution note (required)",
                          );
                          if (reason?.trim())
                            void action(
                              `/prediction/admin/reports/${row.id}/resolve`,
                              { reason: reason.trim() },
                            );
                        }}
                      >
                        Resolve report
                      </button>
                    )}
                  </td>
                </tr>
              ),
            )}
          </tbody>
        </table>
      </div>
      {!rows.length && <p>No records.</p>}
      {cursor && <button onClick={() => void load(true)}>Load next 20</button>}
      {selected && (
        <div
          className="modal"
          role="dialog"
          aria-modal="true"
          aria-label="Prediction details"
        >
          <section
            style={{
              maxHeight: "90vh",
              overflowY: "auto",
              width: "min(100%,1000px)",
            }}
          >
            <button onClick={() => setSelected(null)}>Close</button>
            <h2>
              {text(selected.symbol)} {text(selected.condition)} $
              {text(selected.targetPrice)}
            </h2>
            <p>
              {text(selected.displayStatus)} · Expires{" "}
              {text(selected.expiresAt)} UTC
            </p>
            <p>
              Original price {text(selected.referencePrice)} at{" "}
              {text(selected.referenceTimestamp)} ·{" "}
              {text(selected.referenceSource)}
            </p>
            <p>
              Settlement price {text(selected.settlementPrice)} ·{" "}
              {text(selected.settlementSource)} ·{" "}
              {text(selected.settlementTimestamp)}
            </p>
            {selected.generationContext != null && (
              <pre style={{ whiteSpace: "pre-wrap" }}>
                {JSON.stringify(selected.generationContext, null, 2)}
              </pre>
            )}
            {selected.cancellationReason != null && (
              <p>Refund reason: {text(selected.cancellationReason)}</p>
            )}
            {selected.status === "OPEN" && (
              <div className="toolbar">
                <button
                  disabled={busy}
                  onClick={() => {
                    const reason = window.prompt(
                      "Reason for cancellation and full refund (required)",
                    );
                    if (
                      reason?.trim() &&
                      window.confirm(
                        "Cancel this question and refund every pending stake?",
                      )
                    )
                      void action(
                        `/prediction/admin/questions/${selected.id}/cancel`,
                        { reason: reason.trim() },
                      );
                  }}
                >
                  Cancel & refund all
                </button>
                <button
                  disabled={
                    busy || Date.parse(text(selected.expiresAt)) > Date.now()
                  }
                  onClick={() =>
                    void action(
                      `/prediction/admin/questions/${selected.id}/retry`,
                    )
                  }
                >
                  Retry original-price settlement
                </button>
              </div>
            )}
            {selected.creatorId != null && (
              <div className="toolbar">
                <button
                  disabled={busy}
                  onClick={() => {
                    const reason = window.prompt(
                      "Reason to restrict this creator",
                    );
                    if (reason?.trim())
                      void action(
                        `/prediction/admin/users/${selected.creatorId}/creation`,
                        { enabled: false, reason },
                      );
                  }}
                >
                  Restrict creator
                </button>
                <button
                  disabled={busy}
                  onClick={() => {
                    const reason = window.prompt(
                      "Reason to restore creation permission",
                    );
                    if (reason?.trim())
                      void action(
                        `/prediction/admin/users/${selected.creatorId}/creation`,
                        { enabled: true, reason },
                      );
                  }}
                >
                  Restore creation permission
                </button>
              </div>
            )}
            <h3>Positions</h3>
            <div style={{ overflowX: "auto" }}>
              <table>
                <thead>
                  <tr>
                    {[
                      "User",
                      "Mode",
                      "Side",
                      "Stake USD",
                      "Result",
                      "Returned USD",
                    ].map((h) => (
                      <th key={h}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {positions.map((p) => (
                    <tr key={text(p.id)}>
                      <td>{text(p.name)}</td>
                      <td>{text(p.accountMode)}</td>
                      <td>{text(p.side)}</td>
                      <td>{text(p.stake)}</td>
                      <td>{text(p.result)}</td>
                      <td>{text(p.payoutAmount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {positionCursor && (
              <button
                onClick={async () => {
                  const data = (await requestRef.current(
                    `/prediction/admin/questions/${selected.id}/positions?cursor=${positionCursor}`,
                  )) as Row;
                  setPositions((old) => [...old, ...(data.items as Row[])]);
                  setPositionCursor(data.nextCursor as string | null);
                }}
              >
                More positions
              </button>
            )}
          </section>
        </div>
      )}
    </section>
  );
}
