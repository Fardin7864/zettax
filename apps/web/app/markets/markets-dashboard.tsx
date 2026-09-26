"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import {
  changePercent,
  fetchCandles,
  fetchInstruments,
  formatChange,
  formatPrice,
  lastPrice,
  type AssetClass,
  type CandleSeries,
  type Instrument,
} from "../market-data";
import { useCryptoTickers } from "../market-realtime";

const categories: { label: string; value: AssetClass | "ALL" }[] = [
  { label: "All markets", value: "ALL" },
  { label: "Crypto", value: "CRYPTO" },
  { label: "Forex", value: "FOREX" },
  { label: "Stocks", value: "STOCK" },
  { label: "Indices", value: "INDEX" },
  { label: "Commodities", value: "COMMODITY" },
];
const featuredIds = ["btc-usd", "eth-usd", "sol-usd", "eur-usd"];
const movementClass = (value: number) =>
  Number.isFinite(value) ? (value >= 0 ? "positive" : "negative") : "";

export function MarketsDashboard() {
  const [instruments, setInstruments] = useState<Instrument[]>([]);
  const [quotes, setQuotes] = useState<Record<string, CandleSeries>>({});
  const [category, setCategory] = useState<AssetClass | "ALL">("ALL");
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<"default" | "price" | "change">("default");
  const [view, setView] = useState<"grid" | "list">("grid");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const liveTickers = useCryptoTickers(instruments);
  const priceFor = (item: Instrument, series?: CandleSeries) =>
    liveTickers[item.id]?.price ?? lastPrice(series);
  const changeFor = (item: Instrument, series?: CandleSeries) =>
    liveTickers[item.id]?.change ?? changePercent(series);

  useEffect(() => {
    const controller = new AbortController();
    fetchInstruments(controller.signal)
      .then(setInstruments)
      .catch((reason) => {
        if (!controller.signal.aborted)
          setError(String(reason.message || reason));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, []);

  const visible = useMemo(() => {
    const search = query.trim().toLowerCase();
    const result = instruments.filter(
      (item) =>
        (category === "ALL" || item.assetClass === category) &&
        (!search ||
          `${item.symbol} ${item.name}`.toLowerCase().includes(search)),
    );
    if (sort === "price")
      result.sort(
        (a, b) =>
          (priceFor(b, quotes[b.id]) || 0) - (priceFor(a, quotes[a.id]) || 0),
      );
    if (sort === "change")
      result.sort((a, b) => {
        const left = changeFor(a, quotes[a.id]);
        const right = changeFor(b, quotes[b.id]);
        if (!Number.isFinite(left) && !Number.isFinite(right)) return 0;
        return (
          (Number.isFinite(right) ? right : -Infinity) -
          (Number.isFinite(left) ? left : -Infinity)
        );
      });
    return result;
  }, [instruments, category, query, sort, quotes, liveTickers]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (!instruments.length) return;
    const controller = new AbortController();
    const filtered = instruments.filter(
      (item) =>
        (category === "ALL" || item.assetClass === category) &&
        (!query.trim() ||
          `${item.symbol} ${item.name}`
            .toLowerCase()
            .includes(query.trim().toLowerCase())),
    );
    const ids = Array.from(
      new Set([...featuredIds, ...filtered.map((item) => item.id)]),
    );
    const update = async () => {
      for (let start = 0; start < ids.length; start += 5) {
        if (controller.signal.aborted) return;
        const batch = await Promise.allSettled(
          ids
            .slice(start, start + 5)
            .map((id) => fetchCandles(id, "1h", 25, controller.signal)),
        );
        if (controller.signal.aborted) return;
        setQuotes((current) => {
          const next = { ...current };
          for (const result of batch)
            if (result.status === "fulfilled")
              next[result.value.instrumentId] = result.value;
          return next;
        });
      }
    };
    void update();
    const timer = window.setInterval(update, 60_000);
    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [instruments, category, query]);

  const featured = featuredIds
    .map((id) => instruments.find((item) => item.id === id))
    .filter((item): item is Instrument => Boolean(item));

  return (
    <main className="markets-app">
      <div className="markets-intro">
        <div>
          <span className="market-kicker">ZETTAX MARKETS</span>
          <h1>Explore global markets</h1>
          <p>
            Follow prices and discover opportunities across the markets
            available in the Zettax app.
          </p>
        </div>
        <Link href="/demo" className="button button-gold">
          Open demo trading →
        </Link>
      </div>
      <div
        className="markets-category-strip"
        role="tablist"
        aria-label="Market categories"
      >
        {categories.map((item) => (
          <button
            type="button"
            role="tab"
            aria-selected={category === item.value}
            className={category === item.value ? "active" : ""}
            key={item.value}
            onClick={() => setCategory(item.value)}
          >
            {item.label}
          </button>
        ))}
      </div>
      <div className="markets-workspace">
        <aside className="markets-sidebar">
          <strong>Categories</strong>
          {categories.map((item) => (
            <button
              type="button"
              key={item.value}
              className={category === item.value ? "active" : ""}
              onClick={() => setCategory(item.value)}
            >
              <span>{item.label}</span>
              <span>
                {item.value === "ALL"
                  ? instruments.length
                  : instruments.filter(
                      (instrument) => instrument.assetClass === item.value,
                    ).length}
              </span>
            </button>
          ))}
          <div className="markets-sidebar-note">
            Market data is for display. The browser demo uses virtual funds.
          </div>
        </aside>
        <div className="markets-content">
          <section className="featured-market-section">
            <div className="market-section-heading">
              <div>
                <span className="market-kicker">MARKET OVERVIEW</span>
                <h2>Popular markets</h2>
              </div>
              <span className="market-refresh-label">Live crypto prices</span>
            </div>
            <div className="featured-markets">
              {featured.map((item) => {
                const series = quotes[item.id];
                const price = priceFor(item, series);
                const change = changeFor(item, series);
                return (
                  <Link
                    href={`/demo?instrument=${item.id}`}
                    className="featured-market-card"
                    key={item.id}
                  >
                    <div className="featured-market-card-top">
                      <span className="market-coin">
                        {item.baseAsset.slice(0, 1)}
                      </span>
                      <span className="market-card-arrow">↗</span>
                    </div>
                    <strong>{item.name}</strong>
                    <small>{item.symbol}</small>
                    <div className="featured-price">
                      {formatPrice(price, item.pricePrecision)}
                    </div>
                    <span className={movementClass(change)}>
                      {formatChange(change)}{" "}
                      <small>
                        {series?.freshness === "SIMULATED"
                          ? "no current quote"
                          : series?.effectiveInterval === "1h"
                            ? "24h"
                            : "period"}
                      </small>
                    </span>
                  </Link>
                );
              })}
            </div>
          </section>
          <section className="market-list-section">
            <div className="market-section-heading">
              <div>
                <span className="market-kicker">DISCOVER</span>
                <h2>Market prices</h2>
              </div>
              <label className="market-search">
                <span>⌕</span>
                <input
                  aria-label="Search markets"
                  placeholder="Search markets"
                  value={query}
                  onChange={(event) => setQuery(event.target.value)}
                />
              </label>
            </div>
            <div className="market-list-toolbar">
              <div className="market-list-tabs">
                <button
                  className={sort === "default" ? "active" : ""}
                  onClick={() => setSort("default")}
                >
                  All
                </button>
                <button
                  className={sort === "change" ? "active" : ""}
                  onClick={() => setSort("change")}
                >
                  Top gainers
                </button>
                <button
                  className={sort === "price" ? "active" : ""}
                  onClick={() => setSort("price")}
                >
                  Highest price
                </button>
              </div>
              <div className="market-view-switch" aria-label="Market view">
                <button
                  className={view === "grid" ? "active" : ""}
                  onClick={() => setView("grid")}
                  aria-label="Grid view"
                >
                  ▦
                </button>
                <button
                  className={view === "list" ? "active" : ""}
                  onClick={() => setView("list")}
                  aria-label="List view"
                >
                  ☷
                </button>
              </div>
            </div>
            {loading && <p className="market-empty">Loading markets…</p>}
            {error && (
              <p className="market-empty" role="alert">
                {error}
              </p>
            )}
            {!loading && !error && visible.length === 0 && (
              <p className="market-empty">No markets match your search.</p>
            )}
            {view === "grid" && (
              <div className="market-card-grid">
                {visible.map((item) => {
                  const series = quotes[item.id];
                  const change = changeFor(item, series);
                  const values =
                    series && series.freshness !== "SIMULATED"
                      ? series.candles.map((candle) => Number(candle.close))
                      : [];
                  const minimum = Math.min(...values);
                  const maximum = Math.max(...values);
                  const range = maximum - minimum || 1;
                  const sparkline = values
                    .map(
                      (value, index) =>
                        `${(index / Math.max(values.length - 1, 1)) * 100},${35 - ((value - minimum) / range) * 30}`,
                    )
                    .join(" ");
                  return (
                    <Link
                      href={`/demo?instrument=${item.id}`}
                      className="market-snapshot"
                      key={item.id}
                    >
                      <div className="market-snapshot-head">
                        <span className="market-coin">
                          {item.baseAsset.slice(0, 1)}
                        </span>
                        <span>
                          <strong>{item.symbol}</strong>
                          <small>{item.name}</small>
                        </span>
                        <span className="market-card-arrow">↗</span>
                      </div>
                      <div className="market-snapshot-price">
                        {formatPrice(
                          priceFor(item, series),
                          item.pricePrecision,
                        )}
                      </div>
                      <div className="market-snapshot-chart">
                        {sparkline && (
                          <svg
                            viewBox="0 0 100 40"
                            preserveAspectRatio="none"
                            aria-hidden="true"
                          >
                            <polyline
                              points={sparkline}
                              fill="none"
                              stroke={change >= 0 ? "#1fc297" : "#f05266"}
                              strokeWidth="1.8"
                              vectorEffect="non-scaling-stroke"
                            />
                          </svg>
                        )}
                      </div>
                      <div className="market-snapshot-foot">
                        <span className={movementClass(change)}>
                          {formatChange(change)}
                        </span>
                        <span>
                          {series?.freshness === "SIMULATED"
                            ? "No live quote"
                            : series?.effectiveInterval === "1h"
                              ? "24h change"
                              : "Reference change"}
                        </span>
                      </div>
                      <div className="market-snapshot-source">
                        {series
                          ? series.freshness.replaceAll("_", " ")
                          : "Waiting for data"}
                        <span>Open chart →</span>
                      </div>
                    </Link>
                  );
                })}
              </div>
            )}
            {view === "list" && (
              <div className="market-live-table">
                <div className="market-live-head">
                  <span>Name</span>
                  <span>Last price</span>
                  <span>Change</span>
                  <span>Market</span>
                  <span></span>
                </div>
                {visible.map((item) => {
                  const series = quotes[item.id];
                  const change = changeFor(item, series);
                  return (
                    <div className="market-live-row" key={item.id}>
                      <div className="market-live-name">
                        <span className="market-coin">
                          {item.baseAsset.slice(0, 1)}
                        </span>
                        <span>
                          <strong>{item.symbol}</strong>
                          <small>{item.name}</small>
                        </span>
                      </div>
                      <strong>
                        {formatPrice(
                          priceFor(item, series),
                          item.pricePrecision,
                        )}
                      </strong>
                      <span className={movementClass(change)}>
                        {formatChange(change)}
                      </span>
                      <span className="market-type">
                        {item.assetClass.toLowerCase()}
                      </span>
                      <Link href={`/demo?instrument=${item.id}`}>
                        Trade demo ↗
                      </Link>
                    </div>
                  );
                })}
              </div>
            )}
            <p className="markets-source">
              Prices use the Zettax app market-data API. “—” means this provider
              has no current display price. Simulated feeds are excluded from
              current quotes. Crypto change uses available hourly candles; daily
              reference markets use the previous close. Display data can differ
              from execution prices.
            </p>
          </section>
        </div>
      </div>
    </main>
  );
}
