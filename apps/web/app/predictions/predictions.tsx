"use client";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import Link from "next/link";
import Image from "next/image";
import { useCryptoTickers } from "../market-realtime";
import Script from "next/script";
import { io } from "socket.io-client";
import { Header, Footer } from "../site-shell";
import { CandleChart } from "../demo/candle-chart";
import {
  fetchCandles,
  fetchInstruments,
  type CandleSeries,
  type Instrument,
  type MarketInterval,
} from "../market-data";
import "./predictions.css";

type Question = {
  id: string;
  creatorId: string | null;
  creator: string;
  creatorAvatarUrl: string | null;
  symbol: string;
  instrumentId: string;
  condition: string;
  targetPrice: string;
  referencePrice: string;
  referenceSource: string;
  referenceTimestamp: string;
  expiresAt: string;
  status: string;
  outcome: string | null;
  settlementPrice: string | null;
  settlementSource: string | null;
  settlementTimestamp: string | null;
  cancellationReason: string | null;
  participantCount: number;
  yesDemoPool: string;
  noDemoPool: string;
  demoYesPoolShare: number;
  pricePrecision: number;
  generationContext: {
    explanation: string;
    anchorTimestamp: string;
    anchorPrice: string;
  } | null;
};
type Position = {
  id: string;
  question: Question;
  side: string;
  stake: string;
  result: string;
  payoutAmount: string | null;
};
type PageData<T> = { items: T[]; nextCursor: string | null };
type Account = {
  mode: string;
  wallets: { available: string; locked: string }[];
};
type Pending = { userId: string; path: string; body: unknown; key: string };
type GoogleApi = {
  accounts: {
    id: {
      initialize: (options: {
        client_id: string;
        callback: (response: { credential: string }) => void;
      }) => void;
      renderButton: (
        node: HTMLElement,
        options: { theme: string; size: string; width: number },
      ) => void;
      disableAutoSelect: () => void;
    };
  };
};
const money = (v: string | number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(
    Number(v),
  );
const price = (v: string | number, precision: number) =>
  new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: Math.min(12, Math.max(0, precision)),
    maximumFractionDigits: Math.min(12, Math.max(0, precision)),
  }).format(Number(v));
const title = (q: Question) =>
  `Will ${q.symbol} be ${q.condition.toLowerCase()} ${price(q.targetPrice, q.pricePrecision)}?`;
const statusText = (q: Question) =>
  q.status === "OPEN"
    ? new Date(q.expiresAt).getTime() <= Date.now()
      ? "Awaiting result"
      : "Open"
    : q.status === "CANCELLED"
      ? "Refunded"
      : `Resolved · ${q.outcome}`;
async function api<T>(path: string, body?: unknown, key?: string): Promise<T> {
  const response = await fetch(`/api/predictions/${path}`, {
    method: body === undefined ? "GET" : "POST",
    cache: "no-store",
    headers: {
      "Content-Type": "application/json",
      ...(key ? { "Idempotency-Key": key } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const json = await response.json();
  if (!response.ok)
    throw Object.assign(new Error(json.message || "Request failed."), {
      status: response.status,
    });
  return json.data;
}
function Card({
  q,
  p,
  open,
  avatarOrigin,
  currentPrice,
}: {
  q: Question;
  p?: Position;
  open: () => void;
  avatarOrigin: string;
  currentPrice?: number | undefined;
}) {
  const remaining = Math.max(0, new Date(q.expiresAt).getTime() - Date.now());
  return (
    <button className="prediction-card" onClick={open}>
      <div className="prediction-card-meta">
        <span>
          {q.creatorAvatarUrl && avatarOrigin && (
            <Image
              unoptimized
              src={`${avatarOrigin}/api/v1${q.creatorAvatarUrl}`}
              alt=""
              width={24}
              height={24}
              style={{
                borderRadius: "50%",
                verticalAlign: "middle",
                marginRight: 6,
              }}
            />
          )}
          {q.creator} {q.generationContext ? "· Price-based" : ""}
        </span>
        <span className="prediction-state">{statusText(q)}</span>
      </div>
      <h3>{title(q)}</h3>
      <p>
        {currentPrice === undefined
          ? `Reference ${price(q.referencePrice, q.pricePrecision)}`
          : `Current ${price(currentPrice, q.pricePrecision)}`}{" "}
        · Target {price(q.targetPrice, q.pricePrecision)}
      </p>
      <p>
        {remaining
          ? `${Math.floor(remaining / 3600000)}h ${Math.floor(remaining / 60000) % 60}m left`
          : "Closed"}{" "}
        · {q.participantCount} participants
      </p>
      <div className="prediction-pool">
        <span style={{ width: `${q.demoYesPoolShare}%` }} />
      </div>
      <div className="prediction-split">
        <span>YES {q.demoYesPoolShare}%</span>
        <span>{money(Number(q.yesDemoPool) + Number(q.noDemoPool))} pool</span>
        <span>NO {+(100 - q.demoYesPoolShare).toFixed(1)}%</span>
      </div>
      {p && (
        <p>
          {p.side} · {money(p.stake)} · {p.result}
          {p.payoutAmount !== null
            ? ` · Returned ${money(p.payoutAmount)}`
            : ""}
        </p>
      )}
    </button>
  );
}
async function loadedPages<T>(
  path: string,
  pages: number,
): Promise<PageData<T>> {
  let data = await api<PageData<T>>(path);
  const items = [...data.items];
  for (let page = 1; page < pages && data.nextCursor; page++) {
    data = await api<PageData<T>>(
      `${path}${path.includes("?") ? "&" : "?"}cursor=${data.nextCursor}`,
    );
    items.push(...data.items);
  }
  return { items, nextCursor: data.nextCursor };
}
export default function Predictions({ initialId }: { initialId?: string }) {
  const [tab, setTab] = useState("Explore"),
    [sort, setSort] = useState("NEWEST"),
    [source, setSource] = useState(""),
    [filter, setFilter] = useState("OPEN"),
    [search, setSearch] = useState("");
  const [questions, setQuestions] = useState<Question[]>([]),
    [positions, setPositions] = useState<Position[]>([]),
    [cursor, setCursor] = useState<string | null>(null);
  const [selected, setSelected] = useState(initialId || ""),
    [q, setQ] = useState<Question | null>(null),
    [user, setUser] = useState<{ id: string; email: string } | null>(null);
  const [notice, setNotice] = useState(""),
    [error, setError] = useState(""),
    [loading, setLoading] = useState(false),
    [busy, setBusy] = useState(false);
  const [login, setLogin] = useState(false),
    [register, setRegister] = useState(false),
    [create, setCreate] = useState(false),
    [config, setConfig] = useState({ googleClientId: "", socketOrigin: "" });
  const [assets, setAssets] = useState<Instrument[]>([]),
    [asset, setAsset] = useState("btc-usd"),
    [condition, setCondition] = useState("ABOVE"),
    [target, setTarget] = useState(""),
    [expiry, setExpiry] = useState("");
  const [side, setSide] = useState("YES"),
    [stake, setStake] = useState("10.00"),
    [balance, setBalance] = useState("0.00"),
    [series, setSeries] = useState<CandleSeries>(),
    [interval, setIntervalValue] = useState<MarketInterval>("1m"),
    [chartError, setChartError] = useState("");
  const [pending, setPending] = useState<Pending | null>(null),
    [myDetail, setMyDetail] = useState<Position[]>([]);
  const googleNode = useRef<HTMLDivElement>(null),
    mounted = useRef(true),
    loadVersion = useRef(0),
    sending = useRef(false);
  const loadedPageCount = useRef(1);
  const tickers = useCryptoTickers(assets);
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);
  useEffect(() => {
    if (!selected && !create && !login) return;
    const previous = document.activeElement as HTMLElement | null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const dialog = [
      ...document.querySelectorAll<HTMLElement>(".prediction-modal"),
    ].at(-1);
    const focusable = () => [
      ...(dialog?.querySelectorAll<HTMLElement>(
        'button:not(:disabled), a[href], input, select, textarea, [tabindex="0"]',
      ) || []),
    ];
    focusable()[0]?.focus();
    const key = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        if (login) setLogin(false);
        else if (create) setCreate(false);
        else setSelected("");
      }
      if (event.key !== "Tab") return;
      const nodes = focusable(),
        first = nodes[0],
        last = nodes.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    };
    document.addEventListener("keydown", key);
    return () => {
      document.body.style.overflow = overflow;
      document.removeEventListener("keydown", key);
      previous?.focus();
    };
  }, [selected, create, login]);
  const restoreSession = useCallback(async () => {
    try {
      const me = await api<{ id: string; email: string }>("users/me");
      setUser((old) =>
        old?.id === me.id && old?.email === me.email ? old : me,
      );
      const accounts = await api<Account[]>("accounts");
      setBalance(
        accounts.find((a) => a.mode === "DEMO")?.wallets[0]?.available ||
          "0.00",
      );
      const raw = localStorage.getItem(`zettax_prediction_pending:${me.id}`);
      setPending(raw ? JSON.parse(raw) : null);
    } catch {
      setUser(null);
    }
  }, []);
  const load = useCallback(
    async (more = false) => {
      const version = ++loadVersion.current;
      if ((tab === "My predictions" || tab === "Created by me") && !user) {
        setQuestions([]);
        setPositions([]);
        setCursor(null);
        return;
      }
      setLoading(true);
      const query = new URLSearchParams({
        sort,
        ...(tab === "Results"
          ? { status: "SETTLED" }
          : filter
            ? { status: filter }
            : {}),
        ...(source ? { source } : {}),
        ...(search ? { search } : {}),
        ...(more && cursor ? { cursor } : {}),
      });
      try {
        if (tab === "My predictions") {
          const data = await loadedPages<Position>(
            `prediction/mine${more && cursor ? `?cursor=${cursor}` : ""}`,
            more ? 1 : loadedPageCount.current,
          );
          if (version !== loadVersion.current || !mounted.current) return;
          setPositions((prev) =>
            more
              ? [
                  ...prev,
                  ...data.items.filter(
                    (p) => !prev.some((old) => old.id === p.id),
                  ),
                ]
              : data.items,
          );
          setCursor(data.nextCursor);
        } else {
          const data = await loadedPages<Question>(
            `prediction/${tab === "Created by me" ? "created" : "questions"}?${query}`,
            more ? 1 : loadedPageCount.current,
          );
          if (version !== loadVersion.current || !mounted.current) return;
          setQuestions((prev) =>
            more
              ? [
                  ...prev,
                  ...data.items.filter(
                    (p) => !prev.some((old) => old.id === p.id),
                  ),
                ]
              : data.items,
          );
          setCursor(data.nextCursor);
        }
        if (more) loadedPageCount.current++;
        setError("");
      } catch (e) {
        if (version === loadVersion.current) setError((e as Error).message);
      } finally {
        if (version === loadVersion.current) setLoading(false);
      }
    },
    [tab, sort, filter, source, search, user, cursor],
  );
  const loadRef = useRef(load);
  useEffect(() => {
    loadRef.current = load;
  }, [load]);
  useEffect(() => {
    if (!user) return;
    const key = `zettax_prediction_sequence:${user.id}`;
    let sequence = localStorage.getItem(key),
      stopped = false,
      checking = false;
    const check = async () => {
      if (stopped || checking || document.visibilityState !== "visible") return;
      checking = true;
      try {
        const data = await api<{
          events: {
            type: string;
            sequence: string;
            payload: { result: string; payoutAmount: string };
          }[];
          nextSequence: string;
        }>(`prediction/events${sequence ? `?afterSequence=${sequence}` : ""}`);
        if (stopped) return;
        sequence = data.nextSequence;
        localStorage.setItem(key, sequence);
        const settled = data.events.filter(
          (e) => e.type !== "prediction.position.created",
        );
        if (settled.length) {
          const last = settled.at(-1)!;
          setNotice(
            `Prediction ${last.payload.result.toLowerCase()}. Returned ${money(last.payload.payoutAmount)} to your demo wallet.`,
          );
        }
        if (data.events.length) {
          await restoreSession();
          void loadRef.current();
          if (selected) {
            setQ(await api<Question>(`prediction/questions/${selected}`));
            const own = await api<PageData<Position>>(
              `prediction/questions/${selected}/mine`,
            );
            setMyDetail(own.items);
          }
        }
      } catch {
        /* Durable cursor is retried on the next poll/reconnect. */
      } finally {
        checking = false;
      }
    };
    void check();
    const timer = window.setInterval(() => void check(), 2000);
    return () => {
      stopped = true;
      clearInterval(timer);
    };
  }, [user, selected, restoreSession]);
  useEffect(() => {
    loadedPageCount.current = 1;
    const timer = window.setTimeout(() => void loadRef.current(), 200);
    return () => clearTimeout(timer);
  }, [tab, sort, filter, source, search, user]);
  useEffect(() => {
    void restoreSession();
    void api<typeof config>("config")
      .then(setConfig)
      .catch(() => {});
    void fetchInstruments()
      .then((a) => setAssets(a.filter((v) => v.assetClass === "CRYPTO")))
      .catch(() => {});
  }, [restoreSession]);
  useEffect(() => {
    if (!config.socketOrigin) return;
    const socket = io(`${config.socketOrigin}/prediction`, {
      transports: ["websocket"],
    });
    const sync = () => {
      void loadRef.current();
      if (selected)
        void api<Question>(`prediction/questions/${selected}`)
          .then(setQ)
          .catch(() => {});
      if (user) void restoreSession();
    };
    for (const event of [
      "connect",
      "prediction:sync",
      "prediction:created",
      "prediction:changed",
    ])
      socket.on(event, sync);
    const timer = window.setInterval(sync, 15000);
    const visible = () => {
      if (document.visibilityState === "visible") sync();
    };
    document.addEventListener("visibilitychange", visible);
    return () => {
      socket.disconnect();
      clearInterval(timer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [config.socketOrigin, selected, user, restoreSession]);
  useEffect(() => {
    if (!selected) {
      setQ(null);
      return;
    }
    let active = true;
    void api<Question>(`prediction/questions/${selected}`)
      .then((v) => {
        if (active) setQ(v);
      })
      .catch((e) => setError(e.message));
    if (user)
      void api<PageData<Position>>(`prediction/questions/${selected}/mine`)
        .then((data) => {
          if (active) setMyDetail(data.items);
        })
        .catch(() => {});
    return () => {
      active = false;
    };
  }, [selected, user, notice]);
  const chartAssetId = q?.instrumentId;
  useEffect(() => {
    if (!chartAssetId) return;
    const controller = new AbortController();
    const update = () =>
      void fetchCandles(chartAssetId, interval, 150, controller.signal)
        .then((value) => {
          setSeries(value);
          setChartError("");
        })
        .catch((e) => {
          if (!controller.signal.aborted) setChartError(e.message);
        });
    setSeries(undefined);
    update();
    const timer = window.setInterval(update, 5000);
    return () => {
      controller.abort();
      clearInterval(timer);
    };
  }, [chartAssetId, interval]);
  const signIn = useCallback(
    async (path: string, body: unknown) => {
      if (sending.current) return;
      sending.current = true;
      setBusy(true);
      try {
        await api(path, body);
        setLogin(false);
        setNotice("Signed in successfully.");
        await restoreSession();
      } catch (e) {
        setError((e as Error).message);
      } finally {
        setBusy(false);
        sending.current = false;
      }
    },
    [restoreSession],
  );
  const renderGoogle = useCallback(() => {
    const google = (window as unknown as { google?: GoogleApi }).google;
    if (!googleNode.current || !config.googleClientId || !google) return;
    google.accounts.id.initialize({
      client_id: config.googleClientId,
      callback: (response) =>
        void signIn("auth/google", { idToken: response.credential }),
    });
    google.accounts.id.renderButton(googleNode.current, {
      theme: "filled_black",
      size: "large",
      width: 280,
    });
  }, [config.googleClientId, signIn]);
  useEffect(() => {
    if (login) renderGoogle();
  }, [login, renderGoogle]);
  async function send(command: Pending) {
    if (sending.current) return;
    sending.current = true;
    setBusy(true);
    try {
      await api(command.path, command.body, command.key);
      localStorage.removeItem(`zettax_prediction_pending:${command.userId}`);
      setPending(null);
      setCreate(false);
      setNotice("Prediction request completed.");
      await restoreSession();
      await loadRef.current();
      if (selected)
        setQ(await api<Question>(`prediction/questions/${selected}`));
    } catch (e) {
      const failure = e as Error & { status: number };
      if ([400, 403, 404, 409, 429].includes(failure.status)) {
        localStorage.removeItem(`zettax_prediction_pending:${command.userId}`);
        setPending(null);
      }
      setError(failure.message);
    } finally {
      setBusy(false);
      sending.current = false;
    }
  }
  async function submit(path: string, body: unknown) {
    if (!user) {
      setLogin(true);
      return;
    }
    if (pending) {
      setError("Retry your previous request first.");
      return;
    }
    const command = {
      userId: user.id,
      path,
      body,
      key: `prediction:web:${crypto.randomUUID()}`,
    };
    // Persist before sending so navigation or network failure cannot duplicate a stake.
    localStorage.setItem(
      `zettax_prediction_pending:${user.id}`,
      JSON.stringify(command),
    );
    setPending(command);
    await send(command);
  }
  async function publish(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (
      !window.confirm(
        `Publish: Will ${asset} be ${condition.toLowerCase()} $${target} at ${new Date(expiry).toLocaleString()}? Terms cannot be edited.`,
      )
    )
      return;
    await submit("prediction/questions", {
      instrumentId: asset,
      condition,
      targetPrice: target,
      expiresAt: new Date(expiry).toISOString(),
    });
  }
  const total = q ? Number(q.yesDemoPool) + Number(q.noDemoPool) : 0;
  const sidePool = q
    ? Number(side === "YES" ? q.yesDemoPool : q.noDemoPool)
    : 0;
  const estimate =
    Number(stake) > 0
      ? (Number(stake) * (total + Number(stake))) / (sidePool + Number(stake))
      : 0;
  return (
    <>
      <Header />
      <main className="prediction-page container">
        <section className="prediction-hero">
          <div>
            <p className="eyebrow">MARKET PREDICTIONS · DEMO USD</p>
            <h1>
              See the market.
              <br />
              <span>Make your call.</span>
            </h1>
            <p>
              Explore real-price questions, share your outlook, and follow
              transparent, price-verified results.
            </p>
          </div>
          <div className="prediction-account">
            <strong>{user ? money(balance) : "Demo participation"}</strong>
            <p>
              {user
                ? "Available demo balance"
                : "Use your Zettax account to participate"}
            </p>
            <button
              className="button button-gold"
              onClick={() => (user ? setCreate(true) : setLogin(true))}
            >
              ＋ Create prediction
            </button>
            {user ? (
              <button
                className="button"
                onClick={async () => {
                  await api("auth/logout", {});
                  (
                    window as unknown as { google?: GoogleApi }
                  ).google?.accounts.id.disableAutoSelect();
                  setUser(null);
                }}
              >
                Sign out
              </button>
            ) : (
              <button className="button" onClick={() => setLogin(true)}>
                Sign in
              </button>
            )}
          </div>
        </section>
        <div aria-live="polite">
          {notice && (
            <div className="prediction-notice">
              {notice}
              <button
                aria-label="Dismiss notification"
                onClick={() => setNotice("")}
              >
                ×
              </button>
            </div>
          )}
          {error && (
            <div className="prediction-error">
              {error}
              <button
                onClick={() => {
                  setError("");
                  void loadRef.current();
                }}
              >
                Retry
              </button>
            </div>
          )}
          {pending && (
            <div className="prediction-notice">
              Previous request needs reconciliation.{" "}
              <button disabled={busy} onClick={() => void send(pending)}>
                Retry original request
              </button>
            </div>
          )}
        </div>
        <nav className="prediction-tabs" aria-label="Prediction views">
          {["Explore", "My predictions", "Created by me", "Results"].map(
            (value) => (
              <button
                key={value}
                className={tab === value ? "active" : ""}
                onClick={() => {
                  setTab(value);
                  setCursor(null);
                }}
              >
                {value}
              </button>
            ),
          )}
        </nav>
        <div className="prediction-filters">
          <input
            aria-label="Search predictions"
            placeholder="Search crypto markets…"
            value={search}
            maxLength={80}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select
            aria-label="Sort predictions"
            value={sort}
            onChange={(e) => setSort(e.target.value)}
          >
            <option value="NEWEST">Newest</option>
            <option value="ENDING">Ending soon</option>
            <option value="POPULAR">Most participants</option>
          </select>
          <select
            aria-label="Creator filter"
            value={source}
            onChange={(e) => setSource(e.target.value)}
          >
            <option value="">All creators</option>
            <option value="PLATFORM">Zettax</option>
            <option value="MEMBERS">Members</option>
          </select>
          {tab !== "Results" && (
            <select
              aria-label="Status filter"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            >
              <option value="">All states</option>
              <option value="OPEN">Open</option>
              <option value="CLOSED">Awaiting result</option>
              <option value="SETTLED">Resolved</option>
              <option value="CANCELLED">Refunded</option>
            </select>
          )}
        </div>
        {loading && <p role="status">Updating predictions…</p>}
        {!user && ["My predictions", "Created by me"].includes(tab) ? (
          <div className="prediction-empty">
            <h2>Your predictions, all in one place.</h2>
            <button
              className="button button-gold"
              onClick={() => setLogin(true)}
            >
              Sign in
            </button>
          </div>
        ) : (
          <div className="prediction-grid">
            {tab === "My predictions"
              ? positions.map((p) => (
                  <Card
                    key={p.id}
                    q={p.question}
                    avatarOrigin={config.socketOrigin}
                    currentPrice={
                      tickers[p.question.instrumentId] &&
                      Date.now() - tickers[p.question.instrumentId]!.timestamp <
                        15000
                        ? tickers[p.question.instrumentId]!.price
                        : undefined
                    }
                    p={p}
                    open={() => setSelected(p.question.id)}
                  />
                ))
              : questions.map((question) => (
                  <Card
                    key={question.id}
                    q={question}
                    avatarOrigin={config.socketOrigin}
                    currentPrice={
                      tickers[question.instrumentId] &&
                      Date.now() - tickers[question.instrumentId]!.timestamp <
                        15000
                        ? tickers[question.instrumentId]!.price
                        : undefined
                    }
                    open={() => setSelected(question.id)}
                  />
                ))}
          </div>
        )}
        {!loading &&
          !error &&
          (tab === "My predictions"
            ? !positions.length
            : !questions.length) && (
            <p className="prediction-empty">No predictions in this view yet.</p>
          )}
        {cursor && (
          <button
            className="button"
            disabled={loading}
            onClick={() => void load(true)}
          >
            Load more
          </button>
        )}
        <aside className="prediction-disclosure">
          <strong>Clear rules. No guaranteed forecasts.</strong>
          <p>
            Stake splits are participation, not probability. This feature uses
            virtual demo USD only. Returns depend on the final pool; stakes stay
            locked until settlement. Price-source outages are refunded after 24
            hours. Automatic questions use archived price anchors, not
            investment recommendations.
          </p>
        </aside>
        {q && selected && (
          <div
            className="prediction-modal"
            role="dialog"
            aria-modal="true"
            aria-label="Prediction details"
          >
            <div className="prediction-dialog prediction-detail">
              <button
                className="prediction-close"
                onClick={() => setSelected("")}
                aria-label="Close details"
              >
                ×
              </button>
              <p className="eyebrow">
                {q.symbol} · {statusText(q)}
              </p>
              <h2>{title(q)}</h2>
              <p>
                By {q.creator} · Expires{" "}
                {new Date(q.expiresAt).toLocaleString()}
              </p>
              <div className="prediction-detail-layout">
                <div>
                  <div className="prediction-tabs">
                    {(["1m", "5m", "15m", "1h", "1d"] as MarketInterval[]).map(
                      (v) => (
                        <button
                          key={v}
                          className={interval === v ? "active" : ""}
                          onClick={() => setIntervalValue(v)}
                        >
                          {v}
                        </button>
                      ),
                    )}
                  </div>
                  {chartError && <p>{chartError}</p>}
                  <CandleChart
                    candles={series?.candles || []}
                    precision={q.pricePrecision}
                    interval={interval}
                    targetPrice={Number(q.targetPrice)}
                  />
                  <p>
                    Current price:{" "}
                    {series?.candles.at(-1)?.close || "Unavailable"} · Target:{" "}
                    {q.targetPrice}
                  </p>
                  <h3>Verified settlement rules</h3>
                  <p>
                    {q.condition} is strict; equality settles NO. Uses the last
                    archived one-second close before UTC expiry, from{" "}
                    {q.referenceSource}. UTC expiry: {q.expiresAt}.
                  </p>
                  {q.generationContext && (
                    <p>
                      {q.generationContext.explanation} Anchor{" "}
                      {q.generationContext.anchorPrice} at{" "}
                      {q.generationContext.anchorTimestamp}.
                    </p>
                  )}
                  {q.settlementPrice && (
                    <p>
                      Result evidence: {q.settlementPrice} ·{" "}
                      {q.settlementSource} · {q.settlementTimestamp}
                    </p>
                  )}
                  {q.cancellationReason && (
                    <p>Refund reason: {q.cancellationReason}</p>
                  )}
                  <p>
                    No winning stakes: all stakes refunded. Missing verified
                    expiry price: await result, then refund after 24 hours.
                  </p>
                  <Link href={`/predictions/${q.id}`}>
                    Permanent prediction link
                  </Link>
                  <button
                    className="button"
                    onClick={async () => {
                      const url = `${location.origin}/predictions/${q.id}`;
                      try {
                        if (navigator.share)
                          await navigator.share({ title: title(q), url });
                        else {
                          await navigator.clipboard.writeText(url);
                          setNotice("Prediction link copied.");
                        }
                      } catch {
                        /* User may cancel sharing. */
                      }
                    }}
                  >
                    Share
                  </button>
                  {user && (
                    <button
                      className="button"
                      onClick={async () => {
                        const reason = window.prompt(
                          "Why are you reporting this prediction? (500 characters maximum)",
                        );
                        if (!reason?.trim()) return;
                        try {
                          await api(`prediction/questions/${q.id}/report`, {
                            reason: reason.trim().slice(0, 500),
                          });
                          setNotice("Report submitted.");
                        } catch (e) {
                          setError((e as Error).message);
                        }
                      }}
                    >
                      Report
                    </button>
                  )}
                </div>
                <aside className="prediction-participate">
                  <h3>Make your call</h3>
                  <p>Demo available: {money(balance)}</p>
                  <div className="prediction-sides">
                    {["YES", "NO"].map((v) => (
                      <button
                        key={v}
                        className={side === v ? "active" : ""}
                        onClick={() => setSide(v)}
                      >
                        {v}
                      </button>
                    ))}
                  </div>
                  <label>
                    Demo USD stake
                    <input
                      type="number"
                      min="0.01"
                      max="100000"
                      step="0.01"
                      value={stake}
                      onChange={(e) => setStake(e.target.value)}
                    />
                  </label>
                  <p>
                    Illustrative return if correct:{" "}
                    <strong>{money(estimate)}</strong>, including stake.
                    Incorrect: $0.00. Final pool changes this estimate.
                  </p>
                  <p>
                    YES {q.demoYesPoolShare}% · NO{" "}
                    {+(100 - q.demoYesPoolShare).toFixed(1)}% · {money(total)}{" "}
                    pool
                  </p>
                  <button
                    className="button button-gold"
                    disabled={
                      busy ||
                      q.status !== "OPEN" ||
                      Date.parse(q.expiresAt) <= Date.now()
                    }
                    onClick={async () => {
                      if (!user) {
                        setLogin(true);
                        return;
                      }
                      if (
                        !/^\d+(\.\d{1,2})?$/.test(stake) ||
                        +stake < 0.01 ||
                        +stake > 100000
                      ) {
                        setError("Invalid stake.");
                        return;
                      }
                      if (
                        window.confirm(
                          `Lock ${money(stake)} demo USD for ${side}? No early cash-out. Final returns are not guaranteed.`,
                        )
                      )
                        await submit(`prediction/questions/${q.id}/positions`, {
                          side,
                          stake: Number(stake).toFixed(2),
                          accountMode: "DEMO",
                        });
                    }}
                  >
                    {busy ? "Submitting…" : `Predict ${side}`}
                  </button>
                  <h4>Your positions</h4>
                  {myDetail.map((p) => (
                    <p key={p.id}>
                      {p.side} · {money(p.stake)} · {p.result}
                      {p.payoutAmount
                        ? ` · Returned ${money(p.payoutAmount)}`
                        : ""}
                    </p>
                  ))}
                </aside>
              </div>
            </div>
          </div>
        )}
        {create && (
          <div
            className="prediction-modal"
            role="dialog"
            aria-modal="true"
            aria-label="Create prediction"
          >
            <form className="prediction-dialog" onSubmit={publish}>
              <button
                type="button"
                className="prediction-close"
                onClick={() => setCreate(false)}
                aria-label="Close create form"
              >
                ×
              </button>
              <p className="eyebrow">YOUR MARKET OUTLOOK</p>
              <h2>Create a prediction</h2>
              <p>
                Immutable terms, real archived prices, demo participation.
                Maximum five open questions; targets within 50% of the verified
                current price.
              </p>
              <label>
                Crypto market
                <select
                  value={asset}
                  onChange={(e) => setAsset(e.target.value)}
                >
                  {assets.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.symbol} · {a.name}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Condition
                <select
                  value={condition}
                  onChange={(e) => setCondition(e.target.value)}
                >
                  <option value="ABOVE">Above</option>
                  <option value="BELOW">Below</option>
                </select>
              </label>
              <label>
                Target price in USD
                <input
                  required
                  type="number"
                  min="0.000000000001"
                  step="any"
                  value={target}
                  onChange={(e) => setTarget(e.target.value)}
                />
              </label>
              <label>
                Local expiry (10 minutes–30 days ahead)
                <input
                  required
                  type="datetime-local"
                  value={expiry}
                  onChange={(e) => setExpiry(e.target.value)}
                />
              </label>
              <button
                className="button button-gold"
                disabled={busy || !assets.length}
              >
                Preview & publish
              </button>
            </form>
          </div>
        )}
        {login && (
          <div
            className="prediction-modal"
            role="dialog"
            aria-modal="true"
            aria-label="Sign in"
          >
            <form
              className="prediction-dialog"
              onSubmit={(e) => {
                e.preventDefault();
                const data = new FormData(e.currentTarget);
                void signIn(register ? "auth/register" : "auth/login", {
                  [register ? "email" : "identifier"]: data.get("email"),
                  password: data.get("password"),
                });
              }}
            >
              <button
                type="button"
                className="prediction-close"
                onClick={() => setLogin(false)}
                aria-label="Close sign in"
              >
                ×
              </button>
              <h2>
                {register ? "Create your Zettax account" : "Welcome back"}
              </h2>
              <p>The same account and demo wallet as the Zettax app.</p>
              <div ref={googleNode} />
              <Script
                src="https://accounts.google.com/gsi/client"
                onReady={renderGoogle}
              />
              <label>
                Email
                <input
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                />
              </label>
              <label>
                Password
                <input
                  name="password"
                  type="password"
                  minLength={register ? 12 : 1}
                  maxLength={128}
                  autoComplete={register ? "new-password" : "current-password"}
                  required
                />
              </label>
              {register && (
                <p>
                  Use 12+ characters with uppercase, lowercase, number and
                  symbol.
                </p>
              )}
              <button className="button button-gold" disabled={busy}>
                {busy
                  ? "Please wait…"
                  : register
                    ? "Create account"
                    : "Sign in"}
              </button>
              <button
                type="button"
                className="button"
                onClick={() => setRegister(!register)}
              >
                {register ? "Already have an account?" : "Create an account"}
              </button>
              {error && <p role="alert">{error}</p>}
            </form>
          </div>
        )}
      </main>
      <Footer />
    </>
  );
}
