"use client";
import { useEffect, useState, useRef } from "react";
import Image from "next/image";
import {
  startRegistration,
  startAuthentication,
} from "@simplewebauthn/browser";
type Row = Record<string, unknown>;
type Analytics = {
  users: number;
  trades: number;
  tradeVolume: string;
  creditedDeposits: { count: number; amount: string };
  paidWithdrawals: { count: number; amount: string };
  tradeResults: { result: string; count: number }[];
  daily: {
    day: string;
    signups: number;
    trades: number;
    deposits: number;
    withdrawals: number;
  }[];
};
type Field = {
  key: string;
  label?: string;
  value?: string;
  options?: string[];
};
type Action = {
  title: string;
  path: string;
  method?: string;
  fields: Field[];
  purpose?: string;
  change?: { kind: string; targetId: string };
};
const api = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3000/api/v1";
const areas = [
  "overview",
  "deposits",
  "withdrawals",
  "payment-methods",
  "treasury",
  "release",
  "trading",
  "users",
  "kyc",
  "contracts",
  "markets",
  "ledger",
  "risk",
  "audit",
  "admins",
  "roles",
  "changes",
];
const gates = [
  "ENGINEERING",
  "SECURITY",
  "COMPLIANCE",
  "LEGAL",
  "CUSTODY",
  "PAYMENT_PROVIDER",
  "RECONCILIATION",
  "OPERATIONS",
  "TREASURY",
  "EXECUTIVE",
  "COUNTERPARTY_RISK",
];
const str = (v: unknown): string =>
  v == null ? "—" : typeof v === "object" ? JSON.stringify(v) : String(v);
const title = (v: string) =>
  v
    .replaceAll("-", " ")
    .replaceAll("_", " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/^./, (c) => c.toUpperCase());
const array = (v: unknown) => (Array.isArray(v) ? (v as Row[]) : []);
const isPendingFunding = (area: string, status: unknown) =>
  area === "deposits"
    ? status === "PENDING_REVIEW"
    : area === "withdrawals" &&
      ["REQUESTED", "UNDER_REVIEW", "APPROVED", "PROCESSING"].includes(
        String(status),
      );
const number = (value: number) => new Intl.NumberFormat("en-US").format(value);
const money = (value: string) =>
  `৳${new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(Number(value))}`;
const outcomeColors: Record<string, string> = {
  WIN: "#e7ae3f",
  LOSS: "#df6d65",
  DRAW: "#76a7db",
  VOID: "#a79b8c",
  PENDING: "#7bc7a3",
};

function ActivityChart({ daily }: { daily: Analytics["daily"] }) {
  const width = 720;
  const height = 220;
  const left = 40;
  const right = 12;
  const top = 14;
  const bottom = 28;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const max = Math.max(1, ...daily.flatMap((day) => [day.signups, day.trades]));
  const points = (key: "signups" | "trades") =>
    daily
      .map(
        (day, index) =>
          `${left + (index * plotWidth) / Math.max(1, daily.length - 1)},${top + plotHeight * (1 - day[key] / max)}`,
      )
      .join(" ");
  return (
    <div
      className="analytics-chart"
      role="img"
      aria-label="Daily customer registrations and trades over the last 30 days"
    >
      <svg viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none">
        {[0, 0.5, 1].map((fraction) => (
          <g key={fraction}>
            <line
              x1={left}
              x2={width - right}
              y1={top + plotHeight * fraction}
              y2={top + plotHeight * fraction}
              className="chart-grid"
            />
            <text
              x={left - 9}
              y={top + plotHeight * fraction + 4}
              textAnchor="end"
              className="chart-label"
            >
              {number(Math.round(max * (1 - fraction)))}
            </text>
          </g>
        ))}
        <polyline
          points={points("signups")}
          className="chart-line chart-signups"
        />
        <polyline
          points={points("trades")}
          className="chart-line chart-trades"
        />
        {daily.map((day, index) => (
          <circle
            key={day.day}
            cx={left + (index * plotWidth) / Math.max(1, daily.length - 1)}
            cy={top + plotHeight * (1 - day.trades / max)}
            r="8"
            fill="transparent"
          >
            <title>{`${day.day}: ${day.trades} trades, ${day.signups} new customers`}</title>
          </circle>
        ))}
        <text x={left} y={height - 5} className="chart-label">
          {daily[0]?.day.slice(5)}
        </text>
        <text
          x={width - right}
          y={height - 5}
          textAnchor="end"
          className="chart-label"
        >
          {daily[daily.length - 1]?.day.slice(5)}
        </text>
      </svg>
    </div>
  );
}

function OutcomesChart({ results }: { results: Analytics["tradeResults"] }) {
  const total = results.reduce((sum, row) => sum + row.count, 0);
  let offset = 0;
  const slices = results.map((row) => {
    const start = offset;
    offset += total ? (row.count / total) * 100 : 0;
    return `${outcomeColors[row.result] ?? "#b7a88c"} ${start}% ${offset}%`;
  });
  return (
    <div className="outcomes-wrap">
      <div
        className="outcomes-pie"
        role="img"
        aria-label={`Trade outcomes: ${results.map((row) => `${row.result} ${row.count}`).join(", ") || "no trades"}`}
        style={{
          background: total
            ? `conic-gradient(${slices.join(", ")})`
            : "#39332e",
        }}
      >
        <span>
          <strong>{number(total)}</strong>
          <small>trades</small>
        </span>
      </div>
      <ul className="outcomes-legend">
        {results.length ? (
          results.map((row) => (
            <li key={row.result}>
              <span
                className="legend-dot"
                style={{ background: outcomeColors[row.result] ?? "#b7a88c" }}
              />
              {title(row.result)}
              <strong>{number(row.count)}</strong>
            </li>
          ))
        ) : (
          <li>No trades yet</li>
        )}
      </ul>
    </div>
  );
}

export default function Operations() {
  const dialogRef = useRef<HTMLDivElement>(null);
  const detailsDialogRef = useRef<HTMLDivElement>(null);
  const listVersion = useRef(0);
  const completingWithdrawal = useRef(false);
  const [token, setToken] = useState(""),
    [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [me, setMe] = useState<Row>({}),
    [area, setArea] = useState("overview"),
    [data, setData] = useState<Row | Row[] | null>(null),
    [analytics, setAnalytics] = useState<Analytics | null>(null),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState(""),
    [page, setPage] = useState(1),
    [pageSize, setPageSize] = useState(25),
    [search, setSearch] = useState(""),
    [status, setStatus] = useState(""),
    [selected, setSelected] = useState<Row | null>(null),
    [action, setAction] = useState<Action | null>(null),
    [preview, setPreview] = useState(""),
    [queueCounts, setQueueCounts] = useState({ deposits: 0, withdrawals: 0 });
  const [requestImage, setRequestImage] = useState("");
  const [requestImageError, setRequestImageError] = useState("");
  const [requestImageLoading, setRequestImageLoading] = useState(false);
  const fundingDetailsOpen =
    selected !== null && ["deposits", "withdrawals"].includes(area);
  useEffect(() => {
    setRequestImage("");
    setRequestImageError("");
    if (!selected?.evidenceObjectKey || !token) {
      setRequestImageLoading(false);
      return;
    }
    let stopped = false;
    let url = "";
    setRequestImageLoading(true);
    void (async () => {
      try {
        const rows = array(
          await request(
            `/admin/evidence?key=${encodeURIComponent(str(selected.evidenceObjectKey))}`,
          ),
        );
        if (!rows[0]?.id || rows[0].status === "DELETED")
          throw new Error(
            "Screenshot is unavailable or has expired after 7 days.",
          );
        const response = await fetch(
          `${api}/admin/evidence/${str(rows[0].id)}`,
          { headers: { Authorization: `Bearer ${token}` } },
        );
        if (!response.ok) {
          const error = (await response.json().catch(() => ({}))) as Row;
          throw new Error(
            typeof error.message === "string"
              ? error.message
              : "Screenshot could not be loaded.",
          );
        }
        url = URL.createObjectURL(await response.blob());
        if (stopped) URL.revokeObjectURL(url);
        else setRequestImage(url);
      } catch (error) {
        if (!stopped)
          setRequestImageError(
            error instanceof Error
              ? error.message
              : "Screenshot could not be loaded.",
          );
      } finally {
        if (!stopped) setRequestImageLoading(false);
      }
    })();
    return () => {
      stopped = true;
      if (url) URL.revokeObjectURL(url);
    };
  }, [selected?.id, selected?.evidenceObjectKey, token]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!action && !preview && !fundingDetailsOpen) return;
    const previous = document.activeElement as HTMLElement | null;
    const dialog =
      action || preview ? dialogRef.current : detailsDialogRef.current;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const focusable = () =>
      Array.from(
        dialog?.querySelectorAll<HTMLElement>(
          "button:not(:disabled), input:not(:disabled), select:not(:disabled)",
        ) ?? [],
      );
    const firstFocusable = focusable()[0];
    if (firstFocusable) firstFocusable.focus();
    else dialog?.focus();
    function keys(event: KeyboardEvent) {
      if (event.key === "Escape" && !busy) {
        if (preview) setPreview("");
        else if (action) setAction(null);
        else setSelected(null);
      }
      if (event.key === "Tab") {
        const elements = focusable(),
          first = elements[0],
          last = elements[elements.length - 1];
        if (!elements.length) {
          event.preventDefault();
          dialog?.focus();
          return;
        }
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last?.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first?.focus();
        }
      }
    }
    dialog?.addEventListener("keydown", keys);
    return () => {
      dialog?.removeEventListener("keydown", keys);
      document.body.style.overflow = previousOverflow;
      if (previous?.isConnected) previous.focus();
    };
  }, [action, preview, busy, fundingDetailsOpen, selected?.id]);
  async function request(
    path: string,
    method = "GET",
    body?: unknown,
    session = token,
  ) {
    const response = await fetch(`${api}${path}`, {
      method,
      headers: {
        ...(body instanceof FormData
          ? {}
          : { "Content-Type": "application/json" }),
        ...(session ? { Authorization: `Bearer ${session}` } : {}),
      },
      ...(body === undefined
        ? {}
        : { body: body instanceof FormData ? body : JSON.stringify(body) }),
    });
    const json = (await response.json()) as {
      data: Row | Row[];
      message?: string;
      code?: string;
    };
    if (!response.ok) {
      if (response.status === 401) setToken("");
      throw new Error(json.message ?? json.code ?? "Request failed");
    }
    return json.data;
  }
  async function load() {
    if (!token) return;
    const version = ++listVersion.current;
    setBusy(true);
    setMessage("");
    try {
      const path = [
        "overview",
        "deposits",
        "withdrawals",
        "payment-methods",
        "treasury",
        "release",
        "changes",
      ].includes(area)
        ? `/admin/${area}`
        : area === "trading"
          ? "/admin/trading-settings"
          : `/admin/records/${area}?page=${page}&search=${encodeURIComponent(search)}`;
      const [result, dashboard] = await Promise.all([
        request(
          ["deposits", "withdrawals"].includes(area)
            ? `${path}?page=${page}&pageSize=${pageSize}${status ? `&status=${encodeURIComponent(status)}` : ""}`
            : path,
        ),
        area === "overview" &&
        ((me.permissions as string[] | undefined) ?? []).includes(
          "operations.read",
        )
          ? request("/admin/analytics")
          : Promise.resolve(null),
      ]);
      if (version === listVersion.current) {
        setData(result);
        if (area === "overview") setAnalytics(dashboard as Analytics | null);
        if (
          ["deposits", "withdrawals"].includes(area) &&
          !Array.isArray(result) &&
          page > Number(result.totalPages)
        )
          setPage(Number(result.totalPages));
      }
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Loading failed");
    } finally {
      setBusy(false);
    }
  }
  async function completeWithdrawal(row: Row) {
    if (completingWithdrawal.current || busy) return;
    completingWithdrawal.current = true;
    setBusy(true);
    setMessage("");
    try {
      await request(`/admin/withdrawals/${str(row.id)}/done`, "POST");
      setSelected(null);
      await load();
      setMessage("Withdrawal completed. User and admin history updated.");
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "Could not complete withdrawal.",
      );
    } finally {
      completingWithdrawal.current = false;
      setBusy(false);
    }
  }
  function invalidateListRequests() {
    listVersion.current++;
  }
  useEffect(() => {
    void load();
    return invalidateListRequests;
  }, [area, page, pageSize, token, status]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!token) {
      setQueueCounts({ deposits: 0, withdrawals: 0 });
      return;
    }
    let stopped = false;
    const refreshQueues = async () => {
      try {
        const overview = (await request("/admin/overview")) as Row;
        if (stopped) return;
        setQueueCounts({
          deposits: Number(overview.pendingDeposits) || 0,
          withdrawals: Number(overview.pendingWithdrawals) || 0,
        });
        if (area === "overview") setData(overview);
      } catch {
        // The regular page request presents authentication and network errors.
      }
    };
    void refreshQueues();
    const timer = window.setInterval(refreshQueues, 1500);
    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, [area, token]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!token || !["deposits", "withdrawals"].includes(area)) return;
    let stopped = false;
    let refreshing = false;
    const refreshRequests = async () => {
      if (refreshing) return;
      refreshing = true;
      const version = ++listVersion.current;
      try {
        const path = `/admin/${area}?page=${page}&pageSize=${pageSize}${status ? `&status=${encodeURIComponent(status)}` : ""}`;
        const requests = await request(path);
        if (!stopped && version === listVersion.current) {
          setData(requests);
          const rows = Array.isArray(requests)
            ? requests
            : array(requests.items);
          setSelected((current) =>
            current
              ? (rows.find((row) => row.id === current.id) ?? current)
              : null,
          );
          if (!Array.isArray(requests) && page > Number(requests.totalPages))
            setPage(Number(requests.totalPages));
        }
      } catch {
        // Keep the current table visible; the main loader reports errors.
      } finally {
        refreshing = false;
      }
    };
    const timer = window.setInterval(refreshRequests, 1500);
    return () => {
      stopped = true;
      window.clearInterval(timer);
    };
  }, [area, status, token, page, pageSize]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(
    () => () => {
      if (preview) URL.revokeObjectURL(preview);
    },
    [preview],
  );
  async function security(kind: "REGISTER" | "VERIFY") {
    setBusy(true);
    try {
      const challenge = (await request("/admin/auth/security-options", "POST", {
        kind,
      })) as Row;
      const response =
        kind === "REGISTER"
          ? await startRegistration({
              optionsJSON: challenge.options as Parameters<
                typeof startRegistration
              >[0]["optionsJSON"],
            })
          : await startAuthentication({
              optionsJSON: challenge.options as Parameters<
                typeof startAuthentication
              >[0]["optionsJSON"],
            });
      const result = (await request("/admin/auth/security-verify", "POST", {
        kind,
        challengeId: challenge.challengeId,
        response,
      })) as Row;
      const session = str(result.accessToken);
      setToken(session);
      setMe(
        (await request("/admin/auth/me", "GET", undefined, session)) as Row,
      );
      setMessage("Security key verified for five minutes.");
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Security key verification failed",
      );
    } finally {
      setBusy(false);
    }
  }
  async function showEvidence(row: Row) {
    try {
      let id = row.evidenceId ?? row.evidenceReference;
      if (!id && row.evidenceObjectKey) {
        const found = array(
          await request(
            `/admin/evidence?key=${encodeURIComponent(str(row.evidenceObjectKey))}`,
          ),
        );
        id = found[0]?.id;
      }
      if (!id) throw new Error("No evidence attached.");
      const response = await fetch(`${api}/admin/evidence/${str(id)}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!response.ok) throw new Error("Evidence unavailable.");
      setPreview(URL.createObjectURL(await response.blob()));
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Evidence unavailable");
    }
  }
  function command(
    name: string,
    path: string,
    fields: Field[] = [],
    purpose?: string,
    method = "POST",
  ) {
    setAction({
      title: name,
      path,
      fields,
      method,
      ...(purpose ? { purpose } : {}),
    });
  }
  const field = (key: string, value?: unknown, label?: string): Field => ({
    key,
    ...(value == null ? {} : { value: str(value) }),
    ...(label ? { label } : {}),
  });
  function propose(kind: string, targetId: string, fields: Field[]) {
    setAction({
      title: `Propose ${title(kind)} change`,
      path: "/admin/changes",
      fields,
      change: { kind, targetId },
    });
  }
  const records = Array.isArray(data)
    ? data
    : array(data?.items ?? data?.statements ?? data?.approvals);
  const columns =
    area === "deposits"
      ? [
          "createdAt",
          "amount",
          "senderMobile",
          "providerTransactionId",
          "status",
          "verifiedBy",
        ]
      : area === "withdrawals"
        ? ["createdAt", "amount", "receiverMobile", "status", "approvedBy"]
        : area === "payment-methods"
          ? [
              "displayName",
              "accountNumber",
              "accountType",
              "minimumDeposit",
              "maximumDeposit",
              "isEnabled",
            ]
          : area === "treasury"
            ? ["accountReference", "category", "balance", "asOf", "status"]
            : Object.keys(records[0] ?? {}).slice(0, 6);
  function details(row: Row) {
    return (
      <dl className="facts">
        {Object.entries(row).map(([k, v]) => (
          <div key={k}>
            <dt>{title(k)}</dt>
            <dd>{str(v)}</dd>
          </div>
        ))}
      </dl>
    );
  }
  if (!token)
    return (
      <main className="login-shell">
        <section className="login-card">
          <div className="wordmark login-wordmark">
            <Image
              src="/branding/zettax_wordmark.png"
              alt="Zettax"
              width={220}
              height={220}
              priority
            />
            <span>Zettax / Operations</span>
          </div>
          <h1>Operator sign in</h1>
          <p>Review funding, verify evidence and monitor release readiness.</p>
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              setBusy(true);
              try {
                const result = (await request(
                  "/admin/auth/login",
                  "POST",
                  { email, password },
                  "",
                )) as Row;
                const session = str(result.accessToken);
                setMe(
                  (await request(
                    "/admin/auth/me",
                    "GET",
                    undefined,
                    session,
                  )) as Row,
                );
                setPassword("");
                setToken(session);
              } catch (e) {
                setMessage(e instanceof Error ? e.message : "Sign-in failed");
              } finally {
                setBusy(false);
              }
            }}
          >
            <label>
              Email
              <input
                type="email"
                autoComplete="username"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </label>
            <label>
              Password
              <input
                type="password"
                autoComplete="current-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </label>
            <button className="primary" disabled={busy}>
              Sign in
            </button>
          </form>
          <p role="alert">{message}</p>
          <small>Financial approvals require independent operators.</small>
        </section>
      </main>
    );
  return (
    <div className="ops-shell">
      <aside className="ops-sidebar">
        <div className="wordmark">
          <Image
            src="/branding/zettax_mark.png"
            alt="Zettax"
            width={52}
            height={52}
            priority
          />
          <span>
            Zettax<small>Operations</small>
          </span>
        </div>
        <nav aria-label="Operations">
          {areas
            .filter(
              (id) =>
                ((me.permissions as string[] | undefined) ?? []).includes(
                  "operations.read",
                ) || ["overview", "deposits", "withdrawals"].includes(id),
            )
            .map((id) => (
              <button
                key={id}
                className={area === id ? "active" : ""}
                onClick={() => {
                  setArea(id);
                  setPage(1);
                  setStatus("");
                  setSelected(null);
                  setData(null);
                }}
              >
                <span>{title(id)}</span>
                {(id === "deposits"
                  ? queueCounts.deposits
                  : id === "withdrawals"
                    ? queueCounts.withdrawals
                    : 0) > 0 && (
                  <span className="request-badge" aria-label="pending requests">
                    {id === "deposits"
                      ? queueCounts.deposits
                      : queueCounts.withdrawals}
                  </span>
                )}
              </button>
            ))}
        </nav>
        <button
          onClick={() => {
            setToken("");
            setData(null);
            setPreview("");
          }}
        >
          Sign out
        </button>
      </aside>
      <main className="ops-main">
        <header>
          <div>
            <p className="eyebrow">CONTROL CENTER</p>
            <h1>{title(area)}</h1>
          </div>
          <div className="operator">
            <span>{str(me.email)}</span>
            <button
              disabled={busy}
              onClick={() =>
                void security(
                  Number(me.securityKeys) > 0 ? "VERIFY" : "REGISTER",
                )
              }
            >
              {Number(me.securityKeys) > 0
                ? "Verify security key"
                : "Register security key"}
            </button>
            {Number(me.securityKeys) > 0 && (
              <button disabled={busy} onClick={() => void security("REGISTER")}>
                Add backup key
              </button>
            )}
          </div>
        </header>
        <div className="toolbar">
          <button disabled={busy} onClick={() => void load()}>
            {busy ? "Loading…" : "Refresh"}
          </button>
          {["deposits", "withdrawals"].includes(area) && (
            <select
              aria-label="Funding status"
              value={status}
              onChange={(e) => {
                setStatus(e.target.value);
                setPage(1);
                setData(null);
                setSelected(null);
              }}
              style={{ width: "auto" }}
            >
              <option value="">All history</option>
              {(area === "deposits"
                ? [
                    "CREATED",
                    "PENDING_REVIEW",
                    "APPROVED",
                    "CREDITED",
                    "REJECTED",
                    "CANCELLED",
                  ]
                : [
                    "REQUESTED",
                    "UNDER_REVIEW",
                    "APPROVED",
                    "PROCESSING",
                    "PAID",
                    "REJECTED",
                    "CANCELLED",
                  ]
              ).map((value) => (
                <option key={value} value={value}>
                  {title(value)}
                </option>
              ))}
            </select>
          )}
          {["deposits", "withdrawals"].includes(area) && (
            <>
              <select
                aria-label="Requests per page"
                value={pageSize}
                style={{ width: "auto" }}
                disabled={busy}
                onChange={(e) => {
                  setPageSize(Number(e.target.value));
                  setPage(1);
                  setData(null);
                  setSelected(null);
                }}
              >
                {[10, 25, 50, 100].map((size) => (
                  <option key={size} value={size}>
                    {size} per page
                  </option>
                ))}
              </select>
              <button
                disabled={busy || page === 1}
                onClick={() => {
                  setPage((p) => p - 1);
                  setData(null);
                  setSelected(null);
                }}
              >
                Previous
              </button>
              <span aria-live="polite">
                Page {page} of{" "}
                {data && !Array.isArray(data)
                  ? Number(data.totalPages) || 1
                  : 1}
                {data && !Array.isArray(data)
                  ? ` · ${Number(data.total) || 0} requests`
                  : ""}
              </span>
              <button
                disabled={
                  busy ||
                  !data ||
                  Array.isArray(data) ||
                  page >= Number(data.totalPages)
                }
                onClick={() => {
                  setPage((p) => p + 1);
                  setData(null);
                  setSelected(null);
                }}
              >
                Next
              </button>
            </>
          )}
          {[
            "users",
            "kyc",
            "contracts",
            "markets",
            "ledger",
            "risk",
            "audit",
            "admins",
          ].includes(area) && (
            <>
              <input
                aria-label="Customer email search"
                placeholder="Customer email search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
              <button onClick={() => void load()}>Search</button>
              <button
                disabled={page === 1}
                onClick={() => setPage((p) => p - 1)}
              >
                Previous
              </button>
              <span>Page {page}</span>
              <button
                disabled={records.length < 50}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </button>
            </>
          )}
          {area === "treasury" && (
            <button
              className="primary"
              onClick={() =>
                command(
                  "Add treasury statement",
                  "/admin/treasury",
                  [
                    field("accountReference"),
                    { key: "category", options: ["CUSTOMER", "RESERVE"] },
                    field("balance", undefined, "Balance in BDT"),
                    field("asOf", undefined, "Statement time (UTC ISO)"),
                    field("notes"),
                  ],
                  "TREASURY",
                )
              }
            >
              Add statement
            </button>
          )}
          {area === "release" && (
            <button
              onClick={() =>
                command(
                  "Record office-held legal approval",
                  "/admin/release/approve",
                  [
                    { key: "gate", options: ["LEGAL", "COMPLIANCE"] },
                    field(
                      "officeReference",
                      undefined,
                      "Office record ID, custodian, approval date and product/jurisdiction scope",
                    ),
                    field("expiresAt", undefined, "Expires at (UTC ISO)"),
                    field(
                      "notes",
                      undefined,
                      "Authorized sign-off and findings",
                    ),
                  ],
                )
              }
            >
              Reference office-held documents
            </button>
          )}
          {area === "release" && (
            <button
              className="primary"
              onClick={() =>
                command(
                  "Record authorized release sign-off",
                  "/admin/release/approve",
                  [
                    { key: "gate", options: gates },
                    field("expiresAt", undefined, "Expires at (UTC ISO)"),
                    field(
                      "notes",
                      undefined,
                      "Approval scope and signed findings",
                    ),
                  ],
                  "RELEASE",
                )
              }
            >
              Record sign-off
            </button>
          )}
        </div>
        {message && (
          <div className="notice" role="alert">
            {message}
          </div>
        )}
        {area === "overview" && data && !Array.isArray(data) && (
          <>
            <div className="ops-metrics">
              {analytics ? (
                <>
                  <article>
                    <p>Customers</p>
                    <strong>{number(analytics.users)}</strong>
                    <small>All registered accounts</small>
                  </article>
                  <article>
                    <p>Trades placed</p>
                    <strong>{number(analytics.trades)}</strong>
                    <small>All time</small>
                  </article>
                  <article>
                    <p>Trade volume</p>
                    <strong>{money(analytics.tradeVolume)}</strong>
                    <small>Virtual BDT staked</small>
                  </article>
                  <article>
                    <p>Credited deposits</p>
                    <strong>{money(analytics.creditedDeposits.amount)}</strong>
                    <small>
                      {number(analytics.creditedDeposits.count)} completed
                      requests
                    </small>
                  </article>
                  <article>
                    <p>Paid withdrawals</p>
                    <strong>{money(analytics.paidWithdrawals.amount)}</strong>
                    <small>
                      {number(analytics.paidWithdrawals.count)} completed
                      requests
                    </small>
                  </article>
                  <article>
                    <p>New customers</p>
                    <strong>
                      {number(
                        analytics.daily.reduce(
                          (sum, day) => sum + day.signups,
                          0,
                        ),
                      )}
                    </strong>
                    <small>Last 30 days</small>
                  </article>
                </>
              ) : (
                <article>
                  <p>Customers</p>
                  <strong>{str(data.users)}</strong>
                </article>
              )}
              <article>
                <p>Deposits to review</p>
                <strong>{str(data.pendingDeposits)}</strong>
                <small>Awaiting admin action</small>
              </article>
              <article>
                <p>Withdrawals in progress</p>
                <strong>{str(data.pendingWithdrawals)}</strong>
                <small>Not yet completed</small>
              </article>
            </div>
            {analytics && (
              <div className="analytics-grid">
                <section className="ops-panel analytics-activity">
                  <div className="analytics-heading">
                    <div>
                      <h2>Platform activity</h2>
                      <p>Daily registrations and trades · last 30 days · UTC</p>
                    </div>
                    <div className="chart-key">
                      <span>
                        <i className="key-signups" />
                        Customers
                      </span>
                      <span>
                        <i className="key-trades" />
                        Trades
                      </span>
                    </div>
                  </div>
                  <ActivityChart daily={analytics.daily} />
                </section>
                <section className="ops-panel">
                  <h2>Trade outcomes</h2>
                  <p>All-time contract results</p>
                  <OutcomesChart results={analytics.tradeResults} />
                </section>
                <section className="ops-panel">
                  <h2>Funding activity</h2>
                  <p>Completed requests in the last 30 days · UTC</p>
                  {(
                    [
                      ["Credited deposits", "deposits"],
                      ["Paid withdrawals", "withdrawals"],
                    ] as const
                  ).map(([label, key]) => {
                    const count = analytics.daily.reduce(
                      (sum, day) => sum + day[key],
                      0,
                    );
                    const otherKey =
                      key === "deposits" ? "withdrawals" : "deposits";
                    const otherCount = analytics.daily.reduce(
                      (sum, day) => sum + day[otherKey],
                      0,
                    );
                    return (
                      <div className="funding-bar-row" key={key}>
                        <span>{label}</span>
                        <div className="funding-bar-track">
                          <div
                            className={`funding-bar ${key}`}
                            style={{
                              width: `${(count / Math.max(1, count, otherCount)) * 100}%`,
                            }}
                          />
                        </div>
                        <strong>{number(count)}</strong>
                      </div>
                    );
                  })}
                  <small>
                    Counts reflect credited deposits and paid withdrawals, not
                    pending requests.
                  </small>
                </section>
              </div>
            )}
          </>
        )}
        {["treasury", "release"].includes(area) &&
          data &&
          !Array.isArray(data) && (
            <section className="ops-panel">
              <h2>
                {area === "treasury" ? "Verified backing" : "Release checklist"}
              </h2>
              {area === "release" && (
                <>
                  <p>
                    Version: {str(data.version)} ·{" "}
                    {data.ready
                      ? "Ready for separately authorized activation"
                      : "Not ready"}
                  </p>
                  <div className="gate-list">
                    {((data.missing as string[]) ?? []).map((g) => (
                      <span className="blocked" key={g}>
                        {title(g)} pending
                      </span>
                    ))}
                  </div>
                </>
              )}
              {details(
                ((area === "treasury" ? data.summary : data.treasury) as Row) ??
                  {},
              )}
            </section>
          )}
        {area === "trading" && data && !Array.isArray(data) && (
          <section className="ops-panel">
            <h2>Proportional contract terms</h2>
            <p>
              BUY follows the price return; SELL uses the inverse. Losses stop
              at the customer’s stake.
            </p>
            {details(data)}
            <button
              className="primary"
              onClick={() =>
                propose("TRADING_FEE", "trading.profitFeeRate", [
                  field(
                    "rate",
                    data.profitFeeRate,
                    "Fee rate: 0 = 0%; 0.1 = 10%",
                  ),
                ])
              }
            >
              Change fee
            </button>
          </section>
        )}
        {!["overview", "trading"].includes(area) && (
          <section className="ops-panel">
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    {columns.map((k) => (
                      <th key={k}>{title(k)}</th>
                    ))}
                    <th>Review</th>
                  </tr>
                </thead>
                <tbody>
                  {records.map((row, i) => (
                    <tr
                      key={str(row.id ?? i)}
                      className={`${["deposits", "withdrawals"].includes(area) ? "funding-row" : ""} ${isPendingFunding(area, row.status) ? "pending-row" : ""}`}
                      tabIndex={
                        ["deposits", "withdrawals"].includes(area)
                          ? 0
                          : undefined
                      }
                      onClick={
                        ["deposits", "withdrawals"].includes(area)
                          ? () => setSelected(row)
                          : undefined
                      }
                      onKeyDown={(event) => {
                        if (
                          event.target === event.currentTarget &&
                          ["deposits", "withdrawals"].includes(area) &&
                          (event.key === "Enter" || event.key === " ")
                        ) {
                          event.preventDefault();
                          setSelected(row);
                        }
                      }}
                    >
                      {columns.map((k) => (
                        <td key={k}>
                          {typeof row[k] === "object"
                            ? "View details"
                            : str(row[k])}
                        </td>
                      ))}
                      <td>
                        <button
                          onClick={(event) => {
                            event.stopPropagation();
                            setSelected(row);
                          }}
                        >
                          Open
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {!records.length && (
              <p className="empty">
                {busy ? "Loading records…" : "No records to show."}
              </p>
            )}
          </section>
        )}
        {selected && (
          <div
            className={
              fundingDetailsOpen ? "modal request-details-modal" : undefined
            }
            ref={detailsDialogRef}
            role={fundingDetailsOpen ? "dialog" : undefined}
            tabIndex={fundingDetailsOpen ? -1 : undefined}
            aria-hidden={
              fundingDetailsOpen && (Boolean(action) || Boolean(preview))
                ? true
                : undefined
            }
            aria-modal={fundingDetailsOpen ? true : undefined}
            aria-label={
              fundingDetailsOpen
                ? `${area === "deposits" ? "Deposit" : "Withdrawal"} request details`
                : undefined
            }
            onClick={(event) => {
              if (
                fundingDetailsOpen &&
                event.target === event.currentTarget &&
                !busy
              )
                setSelected(null);
            }}
          >
            <section className="ops-panel">
              <button
                className="close"
                disabled={busy}
                onClick={() => setSelected(null)}
              >
                Close details
              </button>
              <h2>
                {fundingDetailsOpen
                  ? `${area === "deposits" ? "Deposit" : "Withdrawal"} request details`
                  : "Record details"}
              </h2>
              {fundingDetailsOpen && message && (
                <div className="notice" role="alert">
                  {message}
                </div>
              )}
              {details(selected)}
              {area === "deposits" && (
                <div className="deposit-screenshot">
                  <h3>Deposit screenshot</h3>
                  {requestImageLoading && <p>Loading screenshot…</p>}
                  {requestImageError && <p role="alert">{requestImageError}</p>}
                  {!selected.evidenceObjectKey && (
                    <p>No screenshot attached. Screenshots are optional.</p>
                  )}
                  {requestImage && (
                    <Image
                      src={requestImage}
                      width={600}
                      height={800}
                      alt="Deposit screenshot"
                      unoptimized
                      style={{
                        width: "100%",
                        maxWidth: 500,
                        height: "auto",
                        borderRadius: 12,
                      }}
                    />
                  )}
                </div>
              )}
              <div className="actions">
                {Boolean(
                  selected.evidenceObjectKey ||
                  selected.evidenceId ||
                  (selected.evidenceReference &&
                    !str(selected.evidenceReference).startsWith("office:")),
                ) && (
                  <button onClick={() => void showEvidence(selected)}>
                    View private evidence
                  </button>
                )}
                {area === "deposits" &&
                  selected.status === "PENDING_REVIEW" && (
                    <>
                      <button
                        onClick={() =>
                          command(
                            selected.virtualFunding
                              ? "Record virtual deposit review"
                              : "Verify actual provider transfer",
                            `/admin/deposits/${str(selected.id)}/verify`,
                            [
                              field(
                                "reference",
                                undefined,
                                selected.virtualFunding
                                  ? "Virtual review reference"
                                  : "Provider statement / verification reference",
                              ),
                            ],
                          )
                        }
                      >
                        {selected.virtualFunding
                          ? "Record review"
                          : "Verify transfer"}
                      </button>
                      <button
                        onClick={() =>
                          command(
                            selected.virtualFunding
                              ? "Approve virtual deposit credit"
                              : "Approve verified deposit credit",
                            `/admin/deposits/${str(selected.id)}/approve`,
                          )
                        }
                      >
                        Approve credit
                      </button>
                      <button
                        onClick={() =>
                          command(
                            "Reject deposit",
                            `/admin/deposits/${str(selected.id)}/reject`,
                            [field("reason")],
                          )
                        }
                      >
                        Reject
                      </button>
                    </>
                  )}
                {area === "withdrawals" &&
                  !["PAID", "REJECTED", "CANCELLED"].includes(
                    str(selected.status),
                  ) && (
                    <>
                      {selected.virtualFunding === true && (
                        <button
                          className="primary"
                          disabled={busy}
                          onClick={() => void completeWithdrawal(selected)}
                        >
                          Done
                        </button>
                      )}
                    </>
                  )}
                {area === "payment-methods" && (
                  <button
                    onClick={() =>
                      propose("PAYMENT_METHOD", str(selected.id), [
                        field("accountNumber", selected.accountNumber),
                        {
                          key: "accountType",
                          options: ["PERSONAL", "AGENT"],
                          value: str(selected.accountType),
                        },
                        field("instructions", selected.instructions),
                        field("minimumDeposit", selected.minimumDeposit),
                        field("maximumDeposit", selected.maximumDeposit),
                        {
                          key: "isEnabled",
                          options: ["true", "false"],
                          value: str(selected.isEnabled),
                        },
                      ])
                    }
                  >
                    Edit receiving details
                  </button>
                )}
                {area === "treasury" && selected.status === "PENDING" && (
                  <button
                    onClick={() =>
                      command(
                        "Independent treasury review",
                        `/admin/treasury/${str(selected.id)}/review`,
                        [
                          {
                            key: "decision",
                            options: ["APPROVED", "REJECTED"],
                          },
                        ],
                      )
                    }
                  >
                    Review statement
                  </button>
                )}
                {area === "changes" && selected.status === "PENDING" && (
                  <button
                    onClick={() =>
                      command(
                        "Independent change review",
                        `/admin/changes/${str(selected.id)}/review`,
                        [
                          {
                            key: "decision",
                            options: ["APPROVED", "REJECTED"],
                          },
                        ],
                      )
                    }
                  >
                    Review proposed change
                  </button>
                )}
                {area === "users" && (
                  <button
                    onClick={() =>
                      propose(
                        "USER_CONTROLS",
                        str(selected.id),
                        [
                          "depositEnabled",
                          "withdrawalEnabled",
                          "tradingEnabled",
                        ].map((key) => ({
                          key,
                          value: str(selected[key]),
                          options: ["false", "true"],
                        })),
                      )
                    }
                  >
                    Propose account controls
                  </button>
                )}
                {area === "markets" && (
                  <button
                    onClick={() =>
                      propose("MARKET", str(selected.id), [
                        {
                          key: "realEnabled",
                          value: str(selected.realEnabled),
                          options: ["false", "true"],
                        },
                      ])
                    }
                  >
                    Propose market availability
                  </button>
                )}
                {area === "kyc" && (
                  <button
                    onClick={() =>
                      propose("KYC_REVIEW", str(selected.id), [
                        {
                          key: "status",
                          options: [
                            "MORE_INFO_REQUIRED",
                            "REJECTED",
                            "APPROVED",
                          ],
                        },
                        field(
                          "notes",
                          undefined,
                          "Checks performed and findings (minimum 20 characters)",
                        ),
                      ])
                    }
                  >
                    Propose identity review
                  </button>
                )}
                {area === "admins" && (
                  <button
                    onClick={() =>
                      propose("ADMIN_ROLE", str(selected.id), [
                        field(
                          "roleId",
                          undefined,
                          "Role ID from the Roles directory",
                        ),
                        { key: "remove", options: ["false", "true"] },
                      ])
                    }
                  >
                    Propose role assignment
                  </button>
                )}
                {area === "release" && !selected.revokedAt && (
                  <button
                    onClick={() =>
                      command(
                        "Revoke release sign-off",
                        `/admin/release/${str(selected.id)}/revoke`,
                      )
                    }
                  >
                    Revoke approval
                  </button>
                )}
              </div>
            </section>
          </div>
        )}
        {action && (
          <div
            className="modal"
            ref={dialogRef}
            role="dialog"
            aria-modal="true"
            aria-label={action.title}
          >
            <section>
              <h2>{action.title}</h2>
              <p>
                Changes are audited. The checker must be different from the
                maker where independent review is required.
              </p>
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  setBusy(true);
                  setMessage("");
                  const form = new FormData(e.currentTarget),
                    body: Row = {};
                  for (const f of action.fields)
                    body[f.key] = [
                      "isEnabled",
                      "depositEnabled",
                      "withdrawalEnabled",
                      "tradingEnabled",
                      "realEnabled",
                      "remove",
                    ].includes(f.key)
                      ? form.get(f.key) === "true"
                      : form.get(f.key);
                  try {
                    if (action.purpose) {
                      const file = form.get("file");
                      if (!(file instanceof File) || !file.size)
                        throw new Error("Attach an evidence image.");
                      const upload = new FormData();
                      upload.set("file", file);
                      upload.set("purpose", action.purpose);
                      const saved = (await request(
                        "/admin/evidence",
                        "POST",
                        upload,
                      )) as Row;
                      body[
                        action.purpose === "WITHDRAWAL"
                          ? "evidenceObjectKey"
                          : "evidenceId"
                      ] =
                        action.purpose === "WITHDRAWAL"
                          ? saved.objectKey
                          : saved.id;
                    }
                    const result = await request(
                      action.path,
                      action.method ?? "POST",
                      action.change
                        ? { ...action.change, payload: body }
                        : body,
                    );
                    if (action.path === "/admin/auth/confirm-password") {
                      setToken(str((result as Row).accessToken));
                    }
                    setAction(null);
                    setSelected(null);
                    await load();
                    setMessage(
                      action.change
                        ? "Change proposed. A different authorized operator must approve it in Changes."
                        : "Action recorded.",
                    );
                  } catch (e) {
                    setMessage(
                      e instanceof Error ? e.message : "Action failed",
                    );
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                {action.fields.map((f) => (
                  <label key={f.key}>
                    {f.label ?? title(f.key)}
                    {f.options ? (
                      <select
                        name={f.key}
                        defaultValue={f.value ?? f.options[0]}
                      >
                        {f.options.map((o) => (
                          <option key={o}>{o}</option>
                        ))}
                      </select>
                    ) : (
                      <input
                        type={f.key === "password" ? "password" : "text"}
                        autoComplete={
                          f.key === "password" ? "current-password" : undefined
                        }
                        name={f.key}
                        defaultValue={f.value ?? ""}
                        required
                      />
                    )}
                  </label>
                ))}
                {action.purpose && (
                  <label>
                    Supporting image (PNG/JPEG, 5 MB maximum)
                    <input
                      name="file"
                      type="file"
                      accept="image/png,image/jpeg"
                      required
                    />
                  </label>
                )}
                <div className="actions">
                  <button className="primary" disabled={busy}>
                    {busy ? "Processing…" : "Confirm action"}
                  </button>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => setAction(null)}
                  >
                    Cancel
                  </button>
                </div>
                {message && <p role="alert">{message}</p>}
              </form>
            </section>
          </div>
        )}
        {preview && (
          <div
            ref={dialogRef}
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-label="Private evidence"
          >
            <section>
              <button onClick={() => setPreview("")}>Close evidence</button>
              <Image
                src={preview}
                width={900}
                height={1200}
                alt="Private evidence"
                unoptimized
                style={{ width: "100%", height: "auto" }}
              />
            </section>
          </div>
        )}
      </main>
    </div>
  );
}
