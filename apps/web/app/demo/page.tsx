"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Footer, Header } from "../site-shell";
import { CandleChart } from "./candle-chart";
import {
  connectMarketCandle,
  mergeRealtimeCandle,
  useCryptoTickers,
} from "../market-realtime";
import {
  changePercent,
  fetchCandles,
  fetchInstruments,
  formatChange,
  formatPrice,
  lastPrice,
  type CandleSeries,
  type Instrument,
  type MarketInterval,
} from "../market-data";

type Holding = { quantity: number; average: number };
type Order = {
  id: string;
  time: string;
  instrumentId: string;
  symbol: string;
  side: "buy" | "sell";
  type: "market" | "limit";
  quantity: number;
  price: number;
  status: "open" | "filled";
};
type DemoState = {
  cash: number;
  holdings: Record<string, Holding>;
  orders: Order[];
};
type Depth = { bids: [string, string][]; asks: [string, string][] };
type Trade = {
  id: number;
  price: string;
  qty: string;
  time: number;
  isBuyerMaker: boolean;
};
const initial: DemoState = { cash: 100_000, holdings: {}, orders: [] };
const demoStorageKey = "zettax-web-demo-v2";
const intervals: MarketInterval[] = [
  "1m",
  "5m",
  "15m",
  "30m",
  "1h",
  "4h",
  "1d",
  "1w",
  "1M",
];
const featured = [
  "btc-usd",
  "eth-usd",
  "sol-usd",
  "xrp-usd",
  "ada-usd",
  "doge-usd",
  "avax-usd",
  "link-usd",
];
const money = (value: number) =>
  Number.isFinite(value) ? `$${formatPrice(value)}` : "—";
const movementClass = (value: number) =>
  Number.isFinite(value) ? (value >= 0 ? "positive" : "negative") : "";

function fillOrder(state: DemoState, order: Order, price: number): DemoState {
  const old = state.holdings[order.instrumentId] || { quantity: 0, average: 0 };
  const nextQuantity =
    order.side === "buy"
      ? old.quantity + order.quantity
      : Math.max(0, old.quantity - order.quantity);
  const average =
    order.side === "buy" && nextQuantity > 0
      ? (old.quantity * old.average + order.quantity * price) / nextQuantity
      : old.average;
  return {
    cash: state.cash + (order.side === "buy" ? -1 : 1) * order.quantity * price,
    holdings: {
      ...state.holdings,
      [order.instrumentId]: { quantity: nextQuantity, average },
    },
    orders: [
      { ...order, status: "filled" as const, price },
      ...state.orders.filter((item) => item.id !== order.id),
    ].slice(0, 100),
  };
}

export default function DemoPage() {
  const [instruments, setInstruments] = useState<Instrument[]>([]);
  const [selectedId, setSelectedId] = useState("btc-usd");
  const [interval, setInterval] = useState<MarketInterval>("1h");
  const [series, setSeries] = useState<CandleSeries>();
  const [stats, setStats] = useState<CandleSeries>();
  const [quotes, setQuotes] = useState<Record<string, CandleSeries>>({});
  const [depth, setDepth] = useState<Depth>();
  const [trades, setTrades] = useState<Trade[]>([]);
  const [marketSearch, setMarketSearch] = useState("");
  const [marketTab, setMarketTab] = useState<"all" | "crypto" | "other">("all");
  const [bottomTab, setBottomTab] = useState<"open" | "history" | "holdings">(
    "open",
  );
  const [orderType, setOrderType] = useState<"market" | "limit">("market");
  const [buyQuantity, setBuyQuantity] = useState("");
  const [buySpend, setBuySpend] = useState("");
  const [sellQuantity, setSellQuantity] = useState("");
  const [buyLimit, setBuyLimit] = useState("");
  const [sellLimit, setSellLimit] = useState("");
  const [state, setState] = useState<DemoState>(initial);
  const [ready, setReady] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [updatedAt, setUpdatedAt] = useState("");
  const [streamConnected, setStreamConnected] = useState(false);

  useEffect(() => {
    const id = new URLSearchParams(window.location.search).get("instrument");
    if (id && /^[a-z0-9-]+$/.test(id)) setSelectedId(id);
    try {
      const saved = localStorage.getItem(demoStorageKey);
      if (saved) {
        const parsed = JSON.parse(saved) as DemoState;
        if (
          Number.isFinite(parsed.cash) &&
          parsed.holdings &&
          typeof parsed.holdings === "object"
        ) {
          setState({
            cash: parsed.cash,
            holdings: parsed.holdings,
            orders: Array.isArray(parsed.orders) ? parsed.orders : [],
          });
        }
      }
    } catch {
      /* A damaged browser entry starts a fresh virtual portfolio. */
    }
    setReady(true);
    const controller = new AbortController();
    fetchInstruments(controller.signal)
      .then(setInstruments)
      .catch((reason) => {
        if (!controller.signal.aborted)
          setError(String(reason.message || reason));
      });
    return () => controller.abort();
  }, []);

  useEffect(() => {
    if (ready) localStorage.setItem(demoStorageKey, JSON.stringify(state));
  }, [state, ready]);
  const selected = instruments.find((item) => item.id === selectedId);
  const isCrypto = selected?.assetClass === "CRYPTO";
  const liveTickers = useCryptoTickers(instruments);
  useEffect(() => {
    if (selected && selected.assetClass !== "CRYPTO" && interval !== "1d")
      setInterval("1d");
  }, [selected, interval]);

  useEffect(() => {
    if (!selected) return;
    const controller = new AbortController();
    const update = async () => {
      try {
        const result = await fetchCandles(
          selected.id,
          interval,
          200,
          controller.signal,
        );
        if (!controller.signal.aborted) {
          setSeries((current) =>
            current && current.providerTimestamp > result.providerTimestamp
              ? current
              : result,
          );
          setUpdatedAt(new Date().toLocaleTimeString());
          setError(
            result.freshness === "SIMULATED"
              ? "This market currently has simulated data only. A current display quote is unavailable."
              : "",
          );
        }
      } catch (reason) {
        if (!controller.signal.aborted)
          setError(String((reason as Error).message || reason));
      }
    };
    setSeries(undefined);
    void update();
    const timer = window.setInterval(update, 10_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [selected?.id, interval]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!selected || selected.assetClass !== "CRYPTO") {
      setStreamConnected(false);
      return;
    }
    let disposed = false;
    const resync = () => {
      void fetchCandles(selected.id, interval, 200)
        .then((result) => {
          if (!disposed)
            setSeries((current) =>
              current && current.providerTimestamp > result.providerTimestamp
                ? current
                : result,
            );
        })
        .catch(() => {});
    };
    const disconnect = connectMarketCandle(
      selected.id,
      interval,
      (event) => {
        if (disposed) return;
        setSeries((current) => mergeRealtimeCandle(current, event));
        if (interval === "1h")
          setStats((current) => mergeRealtimeCandle(current, event));
        setUpdatedAt(new Date(event.providerTimestamp).toLocaleTimeString());
      },
      (connected) => {
        if (!disposed) setStreamConnected(connected);
      },
      resync,
    );
    return () => {
      disposed = true;
      disconnect();
    };
  }, [selected?.id, interval]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!selected) return;
    const controller = new AbortController();
    const update = () => {
      void fetchCandles(selected.id, "1h", 25, controller.signal)
        .then((result) => {
          if (!controller.signal.aborted)
            setStats((current) =>
              current && current.providerTimestamp > result.providerTimestamp
                ? current
                : result,
            );
        })
        .catch(() => {});
    };
    setStats(undefined);
    update();
    const timer = window.setInterval(update, 30_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [selected?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!instruments.length) return;
    const controller = new AbortController();
    const update = async () => {
      const results = await Promise.allSettled(
        featured.map((id) => fetchCandles(id, "1h", 25, controller.signal)),
      );
      if (controller.signal.aborted) return;
      setQuotes((current) => {
        const next = { ...current };
        for (const result of results)
          if (result.status === "fulfilled")
            next[result.value.instrumentId] = result.value;
        return next;
      });
    };
    void update();
    const timer = window.setInterval(update, 45_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [instruments]);

  useEffect(() => {
    if (!isCrypto) {
      setDepth(undefined);
      setTrades([]);
      return;
    }
    const controller = new AbortController();
    const update = async () => {
      const [book, tape] = await Promise.allSettled([
        fetch(`/api/market/depth?instrumentId=${selectedId}`, {
          signal: controller.signal,
        }).then((response) =>
          response.ok ? (response.json() as Promise<Depth>) : Promise.reject(),
        ),
        fetch(`/api/market/trades?instrumentId=${selectedId}`, {
          signal: controller.signal,
        }).then((response) =>
          response.ok
            ? (response.json() as Promise<Trade[]>)
            : Promise.reject(),
        ),
      ]);
      if (controller.signal.aborted) return;
      setDepth(book.status === "fulfilled" ? book.value : undefined);
      setTrades(tape.status === "fulfilled" ? tape.value : []);
    };
    setDepth(undefined);
    setTrades([]);
    void update();
    const timer = window.setInterval(update, 12_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [selectedId, isCrypto]);

  const activeSeries =
    series?.instrumentId === selectedId &&
    series.requestedInterval === interval &&
    series.freshness !== "SIMULATED"
      ? series
      : undefined;
  const activeStats =
    stats?.instrumentId === selectedId && stats.freshness !== "SIMULATED"
      ? stats
      : undefined;
  const price =
    liveTickers[selectedId]?.price ||
    lastPrice(activeSeries) ||
    lastPrice(activeStats);
  const change = liveTickers[selectedId]?.change ?? changePercent(activeStats);
  const statCandles = activeStats?.candles || [];
  const dayCandles = statCandles.slice(-24);
  const hourlyStats =
    activeStats?.effectiveInterval === "1h" && !activeStats.isSyntheticOhlc;
  const dayHigh =
    hourlyStats && dayCandles.length
      ? Math.max(...dayCandles.map((item) => Number(item.high)))
      : NaN;
  const dayLow =
    hourlyStats && dayCandles.length
      ? Math.min(...dayCandles.map((item) => Number(item.low)))
      : NaN;
  const dayVolume =
    hourlyStats && dayCandles.length
      ? dayCandles.reduce((sum, item) => sum + Number(item.volume || 0), 0)
      : NaN;
  const equity = useMemo(
    () =>
      state.cash +
      instruments.reduce(
        (sum, item) =>
          sum +
          (state.holdings[item.id]?.quantity || 0) *
            (item.id === selectedId
              ? Number.isFinite(price)
                ? price
                : state.holdings[item.id]?.average || 0
              : liveTickers[item.id]?.price ||
                lastPrice(quotes[item.id]) ||
                state.holdings[item.id]?.average ||
                0),
        0,
      ),
    [state, instruments, quotes, liveTickers, selectedId, price],
  );
  const listed = instruments.filter(
    (item) =>
      (marketTab === "all" ||
        (marketTab === "crypto"
          ? item.assetClass === "CRYPTO"
          : item.assetClass !== "CRYPTO")) &&
      (!marketSearch ||
        `${item.symbol} ${item.name}`
          .toLowerCase()
          .includes(marketSearch.toLowerCase())),
  );
  const openOrders = state.orders.filter((item) => item.status === "open");
  const filledOrders = state.orders.filter((item) => item.status === "filled");
  const currentHolding = state.holdings[selectedId]?.quantity || 0;
  const reservedCash = openOrders
    .filter((item) => item.side === "buy")
    .reduce((sum, item) => sum + item.quantity * item.price, 0);
  const reservedHolding = openOrders
    .filter((item) => item.side === "sell" && item.instrumentId === selectedId)
    .reduce((sum, item) => sum + item.quantity, 0);
  const availableCash = Math.max(0, state.cash - reservedCash);
  const buyUnitPrice = orderType === "limit" ? Number(buyLimit) : price;
  const spendQuantity =
    buySpend !== "" && Number.isFinite(buyUnitPrice) && buyUnitPrice > 0
      ? Math.floor(
          (Number(buySpend) / buyUnitPrice) *
            10 ** (selected?.quantityPrecision || 6),
        ) /
        10 ** (selected?.quantityPrecision || 6)
      : 0;

  const placeOrder = useCallback(
    (side: "buy" | "sell") => {
      if (!selected || !Number.isFinite(price) || price <= 0) {
        setMessage(
          "Wait for a current display price before placing a virtual order.",
        );
        return;
      }
      const requestedPrice =
        orderType === "limit"
          ? Number(side === "buy" ? buyLimit : sellLimit)
          : price;
      const spend = Number(buySpend);
      const quantity =
        side === "buy" && buySpend !== ""
          ? requestedPrice > 0
            ? Math.floor(
                (spend / requestedPrice) * 10 ** selected.quantityPrecision,
              ) /
              10 ** selected.quantityPrecision
            : NaN
          : Number(side === "buy" ? buyQuantity : sellQuantity);
      if (
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        !Number.isFinite(requestedPrice) ||
        requestedPrice <= 0
      ) {
        setMessage("Enter a valid quantity and price.");
        return;
      }
      if (
        side === "buy" &&
        ((buySpend !== "" && spend > state.cash - reservedCash + 0.00001) ||
          quantity * requestedPrice > state.cash - reservedCash + 0.00001)
      ) {
        setMessage("Insufficient available virtual USDT.");
        return;
      }
      if (
        side === "sell" &&
        quantity > currentHolding - reservedHolding + 0.00000001
      ) {
        setMessage("Insufficient available virtual holdings.");
        return;
      }
      const order: Order = {
        id: crypto.randomUUID(),
        time: new Date().toISOString(),
        instrumentId: selected.id,
        symbol: selected.symbol,
        side,
        type: orderType,
        quantity,
        price: requestedPrice,
        status: "open",
      };
      const executable =
        orderType === "market" ||
        (side === "buy" ? price <= requestedPrice : price >= requestedPrice);
      setState((current) =>
        executable
          ? fillOrder(current, order, price)
          : { ...current, orders: [order, ...current.orders].slice(0, 100) },
      );
      setMessage(
        executable
          ? `Virtual ${side} order filled at ${formatPrice(price, selected.pricePrecision)}.`
          : "Virtual limit order placed. It will be checked when this market updates.",
      );
      if (side === "buy") {
        setBuyQuantity("");
        setBuySpend("");
      } else setSellQuantity("");
    },
    [
      selected,
      price,
      buyQuantity,
      buySpend,
      sellQuantity,
      buyLimit,
      sellLimit,
      orderType,
      state.cash,
      reservedCash,
      currentHolding,
      reservedHolding,
    ],
  );

  useEffect(() => {
    if (!Number.isFinite(price) || price <= 0) return;
    setState((current) => {
      let next = current;
      for (const order of current.orders.filter(
        (item) =>
          item.status === "open" &&
          item.instrumentId === selectedId &&
          (item.side === "buy" ? price <= item.price : price >= item.price),
      ))
        next = fillOrder(next, order, price);
      return next;
    });
  }, [price, selectedId]);

  return (
    <>
      <Header />
      <main className="trade-app">
        <div className="trade-disclaimer">
          <span className="live-dot" /> Zettax practice trading <span>•</span>{" "}
          Market display data from the app’s API <span>•</span> Orders and
          balances are virtual and stored in this browser
        </div>
        <div className="trade-ticker">
          <div className="trade-ticker-pair">
            <span className="market-coin">
              {selected?.baseAsset.slice(0, 1) || "₿"}
            </span>
            <span>
              <strong>{selected?.symbol || "BTC/USD"}</strong>
              <small>{selected?.name || "Loading market…"}</small>
            </span>
          </div>
          <div className="trade-ticker-price">
            <strong className={movementClass(change)}>
              {formatPrice(price, selected?.pricePrecision)}
            </strong>
            <small>{selected?.quoteAsset || "USD"} display price</small>
          </div>
          <div className="trade-stat">
            <small>
              {!activeStats
                ? "Change"
                : hourlyStats
                  ? "24h Change"
                  : "Previous close"}
            </small>
            <strong className={movementClass(change)}>
              {formatChange(change)}
            </strong>
          </div>
          {hourlyStats ? (
            <>
              <div className="trade-stat">
                <small>24h High</small>
                <strong>
                  {formatPrice(dayHigh, selected?.pricePrecision)}
                </strong>
              </div>
              <div className="trade-stat">
                <small>24h Low</small>
                <strong>{formatPrice(dayLow, selected?.pricePrecision)}</strong>
              </div>
              <div className="trade-stat">
                <small>24h Volume</small>
                <strong>{formatPrice(dayVolume)}</strong>
              </div>
            </>
          ) : (
            activeStats && (
              <div className="trade-stat">
                <small>Reference date</small>
                <strong>
                  {new Date(activeStats.providerTimestamp).toLocaleDateString()}
                </strong>
              </div>
            )
          )}
          <div className="trade-stat trade-source">
            <small>Data source</small>
            <strong>
              {series?.freshness === "SIMULATED"
                ? "No current quote"
                : activeSeries?.provider || "Connecting…"}
            </strong>
          </div>
        </div>
        <div className="trade-layout">
          <aside className="trade-book trade-panel">
            <div className="trade-panel-title">
              <h2>Order book</h2>
              <span>{isCrypto ? "Live depth" : "Crypto only"}</span>
            </div>
            {depth ? (
              <>
                <div className="book-labels">
                  <span>Price (USDT)</span>
                  <span>Amount</span>
                </div>
                <div className="book-rows">
                  {depth.asks
                    .slice(0, 13)
                    .reverse()
                    .map(([level, quantity], index) => (
                      <div
                        className="book-row book-ask"
                        key={`${level}-${index}`}
                      >
                        <span>
                          {formatPrice(Number(level), selected?.pricePrecision)}
                        </span>
                        <span>{formatPrice(Number(quantity), 5)}</span>
                      </div>
                    ))}
                </div>
                <div className="book-mid">
                  {formatPrice(price, selected?.pricePrecision)}{" "}
                  <span>{selected?.symbol}</span>
                </div>
                <div className="book-rows">
                  {depth.bids.slice(0, 13).map(([level, quantity], index) => (
                    <div
                      className="book-row book-bid"
                      key={`${level}-${index}`}
                    >
                      <span>
                        {formatPrice(Number(level), selected?.pricePrecision)}
                      </span>
                      <span>{formatPrice(Number(quantity), 5)}</span>
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <p className="trade-placeholder">
                {isCrypto
                  ? "Loading live order book…"
                  : "Order book is currently available for crypto markets."}
              </p>
            )}
          </aside>
          <div className="trade-center">
            <section className="trade-chart-panel trade-panel">
              <div className="trade-panel-title trade-chart-tabs">
                <h2>Chart</h2>
                <span>Market analysis</span>
                <span>Data</span>
                <span className="trade-live-tag">
                  {streamConnected && <span className="live-dot" />}{" "}
                  {streamConnected
                    ? `Live · ${updatedAt}`
                    : updatedAt
                      ? `Updated ${updatedAt}`
                      : "Connecting"}
                </span>
              </div>
              <div className="trade-timeframes">
                <span>Time</span>
                {intervals.map((item) => (
                  <button
                    key={item}
                    className={interval === item ? "active" : ""}
                    disabled={Boolean(selected && !isCrypto && item !== "1d")}
                    title={
                      selected && !isCrypto && item !== "1d"
                        ? "This provider supplies daily reference data only"
                        : undefined
                    }
                    onClick={() => setInterval(item)}
                  >
                    {item}
                  </button>
                ))}
              </div>
              {error && (
                <p className="trade-error" role="alert">
                  {error}
                </p>
              )}
              <CandleChart
                key={`${selectedId}:${interval}`}
                candles={activeSeries?.candles || []}
                precision={selected?.pricePrecision || 2}
                interval={activeSeries?.effectiveInterval || interval}
                referenceLine={Boolean(activeSeries?.isSyntheticOhlc)}
                emptyLabel={
                  series?.freshness === "SIMULATED"
                    ? "Current chart unavailable for this market."
                    : "Waiting for market candles…"
                }
              />
              <div className="trade-chart-foot">
                {activeSeries
                  ? `${activeSeries.provider} • ${activeSeries.freshness.replaceAll("_", " ")} • ${activeSeries.effectiveInterval}${activeSeries.isSyntheticOhlc ? " • Reference closes" : ""}`
                  : "Waiting for market data"}
                <span>
                  Drag to move through candles · pinch to zoom on touch screens
                  · display prices are not execution quotes.
                </span>
              </div>
            </section>
            <section className="trade-order-panel trade-panel">
              <div className="trade-panel-title">
                <h2>Spot · Practice</h2>
                <span>Virtual balance {money(state.cash)}</span>
              </div>
              <div className="trade-order-types">
                <button
                  className={orderType === "market" ? "active" : ""}
                  onClick={() => setOrderType("market")}
                >
                  Market
                </button>
                <button
                  className={orderType === "limit" ? "active" : ""}
                  onClick={() => setOrderType("limit")}
                >
                  Limit
                </button>
                <span>Orders use virtual funds</span>
              </div>
              <div className="trade-order-grid">
                {(["buy", "sell"] as const).map((side) => (
                  <div className="trade-order-form" key={side}>
                    <div className="trade-available">
                      Available{" "}
                      <strong>
                        {side === "buy"
                          ? `${formatPrice(Math.max(0, state.cash - reservedCash))} USDT`
                          : `${formatPrice(Math.max(0, currentHolding - reservedHolding), selected?.quantityPrecision || 6)} ${selected?.baseAsset || ""}`}
                      </strong>
                    </div>
                    {orderType === "limit" && (
                      <label>
                        Limit price <span>USDT</span>
                        <input
                          type="number"
                          min="0"
                          step="any"
                          placeholder={formatPrice(
                            price,
                            selected?.pricePrecision,
                          )}
                          value={side === "buy" ? buyLimit : sellLimit}
                          onChange={(event) =>
                            side === "buy"
                              ? setBuyLimit(event.target.value)
                              : setSellLimit(event.target.value)
                          }
                        />
                      </label>
                    )}
                    {side === "buy" && (
                      <label>
                        Spend <span>USDT</span>
                        <input
                          type="number"
                          min="0"
                          step="any"
                          placeholder="Enter an amount from your balance"
                          value={buySpend}
                          onChange={(event) => setBuySpend(event.target.value)}
                        />
                      </label>
                    )}
                    {side === "buy" && (
                      <button
                        type="button"
                        className="trade-use-max"
                        onClick={() => setBuySpend(String(availableCash))}
                      >
                        Use max balance
                      </button>
                    )}
                    <label>
                      Amount <span>{selected?.baseAsset || "Asset"}</span>
                      <input
                        type="number"
                        min="0"
                        step="any"
                        placeholder="0.00"
                        value={
                          side === "buy"
                            ? buySpend !== ""
                              ? spendQuantity || ""
                              : buyQuantity
                            : sellQuantity
                        }
                        onChange={(event) => {
                          if (side === "buy") {
                            setBuySpend("");
                            setBuyQuantity(event.target.value);
                          } else setSellQuantity(event.target.value);
                        }}
                      />
                    </label>
                    <div className="trade-estimate">
                      Estimated total{" "}
                      <strong>
                        {money(
                          Number(
                            side === "buy"
                              ? buySpend !== ""
                                ? spendQuantity
                                : buyQuantity
                              : sellQuantity,
                          ) *
                            (orderType === "limit"
                              ? Number(side === "buy" ? buyLimit : sellLimit)
                              : price),
                        )}
                      </strong>
                    </div>
                    <button
                      className={`trade-order-submit ${side}`}
                      onClick={() => placeOrder(side)}
                    >
                      {side === "buy" ? "Buy" : "Sell"}{" "}
                      {selected?.baseAsset || "Asset"}
                    </button>
                  </div>
                ))}
              </div>
              {message && (
                <p className="trade-message" role="status">
                  {message}
                </p>
              )}
            </section>
          </div>
          <aside className="trade-right">
            <section className="trade-panel trade-market-list">
              <label className="trade-search">
                <span>⌕</span>
                <input
                  aria-label="Search trading pairs"
                  placeholder="Search"
                  value={marketSearch}
                  onChange={(event) => setMarketSearch(event.target.value)}
                />
              </label>
              <div className="trade-market-tabs">
                <button
                  className={marketTab === "all" ? "active" : ""}
                  onClick={() => setMarketTab("all")}
                >
                  All
                </button>
                <button
                  className={marketTab === "crypto" ? "active" : ""}
                  onClick={() => setMarketTab("crypto")}
                >
                  Crypto
                </button>
                <button
                  className={marketTab === "other" ? "active" : ""}
                  onClick={() => setMarketTab("other")}
                >
                  Other
                </button>
              </div>
              <div className="trade-market-labels">
                <span>Name</span>
                <span>Last price</span>
                <span>Change</span>
              </div>
              <div className="trade-market-scroll">
                {listed.map((item) => {
                  const quote =
                    item.id === selectedId ? activeStats : quotes[item.id];
                  const ticker = liveTickers[item.id];
                  const movement = ticker?.change ?? changePercent(quote);
                  return (
                    <button
                      className={item.id === selectedId ? "active" : ""}
                      key={item.id}
                      onClick={() => {
                        setSelectedId(item.id);
                        setMessage("");
                        window.history.replaceState(
                          null,
                          "",
                          `/demo?instrument=${item.id}`,
                        );
                      }}
                    >
                      <span>{item.symbol}</span>
                      <span>
                        {formatPrice(
                          ticker?.price ?? lastPrice(quote),
                          item.pricePrecision,
                        )}
                      </span>
                      <span className={movementClass(movement)}>
                        {formatChange(movement)}
                      </span>
                    </button>
                  );
                })}
              </div>
            </section>
            <section className="trade-panel trade-recent">
              <div className="trade-panel-title">
                <h2>Market trades</h2>
                <span>Live recent trades</span>
              </div>
              {trades.length ? (
                <>
                  <div className="trade-market-labels">
                    <span>Price</span>
                    <span>Amount</span>
                    <span>Time</span>
                  </div>
                  {trades
                    .slice()
                    .reverse()
                    .map((trade) => (
                      <div className="recent-trade" key={trade.id}>
                        <span
                          className={
                            trade.isBuyerMaker ? "negative" : "positive"
                          }
                        >
                          {formatPrice(
                            Number(trade.price),
                            selected?.pricePrecision,
                          )}
                        </span>
                        <span>{formatPrice(Number(trade.qty), 5)}</span>
                        <span>{new Date(trade.time).toLocaleTimeString()}</span>
                      </div>
                    ))}
                </>
              ) : (
                <p className="trade-placeholder">
                  {isCrypto
                    ? "Loading recent trades…"
                    : "Recent trades are available for crypto markets."}
                </p>
              )}
            </section>
          </aside>
        </div>
        <section className="trade-history trade-panel">
          <div className="trade-bottom-tabs">
            <button
              className={bottomTab === "open" ? "active" : ""}
              onClick={() => setBottomTab("open")}
            >
              Open Orders ({openOrders.length})
            </button>
            <button
              className={bottomTab === "history" ? "active" : ""}
              onClick={() => setBottomTab("history")}
            >
              Order History
            </button>
            <button
              className={bottomTab === "holdings" ? "active" : ""}
              onClick={() => setBottomTab("holdings")}
            >
              Holdings
            </button>
            <div className="trade-balance-summary">
              Portfolio {money(equity)}{" "}
              <button
                onClick={() => {
                  setState(initial);
                  setMessage("Virtual portfolio reset.");
                }}
              >
                Reset demo
              </button>
            </div>
          </div>
          {bottomTab === "holdings" ? (
            <div className="trade-history-table">
              <div className="trade-history-head">
                <span>Asset</span>
                <span>Quantity</span>
                <span>Average entry</span>
                <span>Estimated value</span>
                <span></span>
              </div>
              {Object.entries(state.holdings)
                .filter(([, holding]) => holding.quantity > 0)
                .map(([id, holding]) => {
                  const item = instruments.find(
                    (instrument) => instrument.id === id,
                  );
                  return (
                    <div className="trade-history-row" key={id}>
                      <span>{item?.symbol || id}</span>
                      <span>{formatPrice(holding.quantity, 6)}</span>
                      <span>{money(holding.average)}</span>
                      <span>
                        {money(
                          holding.quantity *
                            (id === selectedId
                              ? price
                              : lastPrice(quotes[id]) || holding.average),
                        )}
                      </span>
                      <span>Virtual</span>
                    </div>
                  );
                })}
              {Object.values(state.holdings).every(
                (holding) => holding.quantity <= 0,
              ) && (
                <p className="trade-history-empty">No virtual holdings yet.</p>
              )}
            </div>
          ) : (
            <div className="trade-history-table">
              <div className="trade-history-head">
                <span>Date</span>
                <span>Pair</span>
                <span>Type / side</span>
                <span>Price</span>
                <span>Amount</span>
              </div>
              {(bottomTab === "open" ? openOrders : filledOrders).map(
                (order) => (
                  <div className="trade-history-row" key={order.id}>
                    <span>{new Date(order.time).toLocaleString()}</span>
                    <span>{order.symbol}</span>
                    <span
                      className={order.side === "buy" ? "positive" : "negative"}
                    >
                      {order.type} {order.side}
                    </span>
                    <span>{formatPrice(order.price)}</span>
                    <span>
                      {formatPrice(order.quantity, 6)}{" "}
                      {bottomTab === "open" && (
                        <button
                          className="cancel-order"
                          onClick={() =>
                            setState((current) => ({
                              ...current,
                              orders: current.orders.filter(
                                (item) => item.id !== order.id,
                              ),
                            }))
                          }
                        >
                          Cancel
                        </button>
                      )}
                    </span>
                  </div>
                ),
              )}
              {(bottomTab === "open" ? openOrders : filledOrders).length ===
                0 && (
                <p className="trade-history-empty">
                  {bottomTab === "open"
                    ? "You have no open virtual orders."
                    : "Your completed virtual orders will appear here."}
                </p>
              )}
            </div>
          )}
        </section>
        <div className="trade-bottom-note">
          Market prices and depth are informational. This browser demo does not
          place real orders or connect to your Zettax app account.{" "}
          <Link href="/markets">Explore all markets →</Link>
        </div>
      </main>
      <Footer />
    </>
  );
}
