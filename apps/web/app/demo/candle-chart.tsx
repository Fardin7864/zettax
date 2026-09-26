"use client";

import { useMemo, useRef, useState } from "react";
import { formatPrice, type Candle } from "../market-data";

const width = 1000;
const height = 490;
const left = 14;
const right = 91;
const top = 80;
const priceBottom = 363;
const volumeTop = 385;
const volumeBottom = 459;
const plotRight = width - right - 26;

function average(values: number[], end: number, period: number) {
  if (end + 1 < period) return null;
  let sum = 0;
  for (let index = end + 1 - period; index <= end; index++)
    sum += values[index]!;
  return sum / period;
}

export function CandleChart({
  candles,
  precision,
  interval,
  referenceLine = false,
  emptyLabel = "Waiting for market candles…",
}: {
  candles: Candle[];
  precision: number;
  interval: string;
  referenceLine?: boolean;
  emptyLabel?: string;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [view, setView] = useState({ count: 80, offset: 0 });
  const svgRef = useRef<SVGSVGElement>(null);
  const drag = useRef<{ x: number; offset: number } | null>(null);
  const pointers = useRef(new Map<number, number>());
  const pinch = useRef<{
    distance: number;
    count: number;
    offset: number;
  } | null>(null);
  const visibleCount = Math.min(view.count, candles.length);
  const visibleEnd = Math.max(
    visibleCount,
    candles.length -
      Math.min(view.offset, Math.max(0, candles.length - visibleCount)),
  );
  const visibleCandles = candles.slice(visibleEnd - visibleCount, visibleEnd);
  const visibleStart = visibleEnd - visibleCount;
  const allCloses = candles.map((item) => Number(item.close));

  const zoom = (direction: "in" | "out", ratio = 0.5) => {
    setView((current) => {
      const total = candles.length;
      if (total < 12) return current;
      const oldCount = Math.min(current.count, total);
      const nextCount = Math.max(
        12,
        Math.min(
          total,
          Math.round(oldCount * (direction === "in" ? 0.8 : 1.25)),
        ),
      );
      const start = total - current.offset - oldCount;
      const anchor = start + ratio * oldCount;
      const nextStart = anchor - ratio * nextCount;
      const nextOffset = Math.max(
        0,
        Math.min(total - nextCount, Math.round(total - nextStart - nextCount)),
      );
      return { count: nextCount, offset: nextOffset };
    });
  };

  const chart = useMemo(() => {
    const parsed = visibleCandles
      .map((item) => ({
        ...item,
        o: Number(item.open),
        h: Number(item.high),
        l: Number(item.low),
        c: Number(item.close),
        v: Number(item.volume || 0),
      }))
      .filter((item) =>
        [item.o, item.h, item.l, item.c].every(Number.isFinite),
      );
    const lows = parsed.map((item) => (referenceLine ? item.c : item.l));
    const highs = parsed.map((item) => (referenceLine ? item.c : item.h));
    const min = Math.min(...lows);
    const max = Math.max(...highs);
    const padding = (max - min || max * 0.01) * 0.09;
    const floor = min - padding;
    const ceiling = max + padding;
    const plotBottom = referenceLine ? volumeBottom : priceBottom;
    const y = (price: number) =>
      top + ((ceiling - price) / (ceiling - floor)) * (plotBottom - top);
    const slot = (plotRight - left) / parsed.length;
    const x = (index: number) => left + (index + 0.5) * slot;
    const candleWidth = Math.max(2, slot);
    const maxVolume = Math.max(...parsed.map((item) => item.v), 1);
    const ma = (period: number) =>
      parsed
        .map((_, index) => {
          const value = average(allCloses, visibleStart + index, period);
          return value === null
            ? null
            : `${x(index).toFixed(1)},${y(value).toFixed(1)}`;
        })
        .filter((point): point is string => point !== null)
        .join(" ");
    return {
      parsed,
      floor,
      ceiling,
      y,
      x,
      candleWidth,
      maxVolume,
      plotBottom,
      closeLine: parsed
        .map((item, index) => `${x(index).toFixed(1)},${y(item.c).toFixed(1)}`)
        .join(" "),
      ma7: ma(7),
      ma25: ma(25),
      ma99: ma(99),
    };
  }, [visibleCandles, referenceLine, allCloses, visibleStart]);

  if (!chart.parsed.length)
    return <div className="trading-chart-empty">{emptyLabel}</div>;
  const activeIndex = Math.min(
    hover ?? chart.parsed.length - 1,
    chart.parsed.length - 1,
  );
  const active = chart.parsed[activeIndex]!;
  const current = chart.parsed.at(-1)!;
  const activeGlobalIndex = visibleStart + activeIndex;
  const activeChange =
    active.o > 0 ? ((active.c - active.o) / active.o) * 100 : NaN;
  const activeRange =
    active.o > 0 ? ((active.h - active.l) / active.o) * 100 : NaN;
  const priceColor = current.c >= current.o ? "#17bd9c" : "#f3485d";
  const timeFormat: Intl.DateTimeFormatOptions =
    interval === "1d" || interval === "1w" || interval === "1M"
      ? { month: "short", day: "numeric" }
      : { hour: "2-digit", minute: "2-digit" };

  return (
    <div className="trading-chart-wrap">
      <div className="chart-zoom-controls">
        <button
          type="button"
          aria-label="Zoom in"
          title="Zoom in"
          onClick={() => zoom("in")}
        >
          +
        </button>
        <button
          type="button"
          aria-label="Zoom out"
          title="Zoom out"
          onClick={() => zoom("out")}
        >
          −
        </button>
        <button
          type="button"
          aria-label="Reset chart zoom"
          title="Reset chart zoom"
          onClick={() => setView({ count: 80, offset: 0 })}
        >
          Reset
        </button>
      </div>
      <div className="chart-ohlc">
        <span>
          {new Date(active.openTime).toLocaleString("en-US", {
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
            ...(interval === "1d" || interval === "1w" || interval === "1M"
              ? {}
              : { hour: "2-digit", minute: "2-digit" }),
          })}
        </span>
        {!referenceLine && (
          <span>
            Open <b>{formatPrice(active.o, precision)}</b>
          </span>
        )}
        {!referenceLine && (
          <span>
            High <b>{formatPrice(active.h, precision)}</b>
          </span>
        )}
        {!referenceLine && (
          <span>
            Low <b>{formatPrice(active.l, precision)}</b>
          </span>
        )}
        <span>
          Close{" "}
          <b className={active.c >= active.o ? "positive" : "negative"}>
            {formatPrice(active.c, precision)}
          </b>
        </span>
        {!referenceLine && (
          <span>
            Change{" "}
            <b className={activeChange >= 0 ? "positive" : "negative"}>
              {Number.isFinite(activeChange)
                ? `${activeChange >= 0 ? "+" : ""}${activeChange.toFixed(2)}%`
                : "—"}
            </b>
          </span>
        )}
        {!referenceLine && (
          <span>
            Range{" "}
            <b>
              {Number.isFinite(activeRange)
                ? `${activeRange.toFixed(2)}%`
                : "—"}
            </b>
          </span>
        )}
      </div>
      <div className="chart-ma-values">
        {[7, 25, 99].map((period) => {
          const value = average(allCloses, activeGlobalIndex, period);
          return (
            <span key={period} className={`ma-value-${period}`}>
              MA({period}){" "}
              <b>{value === null ? "—" : formatPrice(value, precision)}</b>
            </span>
          );
        })}
      </div>
      <svg
        ref={svgRef}
        className="trading-candle-svg"
        viewBox={`0 0 ${width} ${height}`}
        preserveAspectRatio="none"
        role="img"
        aria-label={
          referenceLine
            ? "Market reference close-price chart with moving averages"
            : "Market candlestick chart with volume and moving averages"
        }
        onMouseLeave={() => setHover(null)}
        onPointerDown={(event) => {
          if (event.pointerType === "mouse" && event.button !== 0) return;
          pointers.current.set(event.pointerId, event.clientX);
          if (pointers.current.size === 1) {
            drag.current = { x: event.clientX, offset: view.offset };
          } else if (pointers.current.size === 2) {
            const [first, second] = [...pointers.current.values()];
            pinch.current = {
              distance: Math.max(1, Math.abs(first! - second!)),
              count: view.count,
              offset: view.offset,
            };
            drag.current = null;
          }
          event.currentTarget.setPointerCapture(event.pointerId);
        }}
        onPointerUp={(event) => {
          pointers.current.delete(event.pointerId);
          pinch.current = null;
          drag.current = null;
          if (event.currentTarget.hasPointerCapture(event.pointerId))
            event.currentTarget.releasePointerCapture(event.pointerId);
        }}
        onPointerCancel={(event) => {
          pointers.current.delete(event.pointerId);
          pinch.current = null;
          drag.current = null;
        }}
        onPointerMove={(event) => {
          if (pointers.current.has(event.pointerId))
            pointers.current.set(event.pointerId, event.clientX);
          if (pinch.current && pointers.current.size === 2) {
            const [first, second] = [...pointers.current.values()];
            const distance = Math.max(1, Math.abs(first! - second!));
            const nextCount = Math.max(
              12,
              Math.min(
                candles.length,
                Math.round(
                  (pinch.current.count * pinch.current.distance) / distance,
                ),
              ),
            );
            setView({
              count: nextCount,
              offset: Math.min(
                Math.max(0, candles.length - nextCount),
                pinch.current.offset,
              ),
            });
            return;
          }
          if (drag.current) {
            const bounds = event.currentTarget.getBoundingClientRect();
            const bars = Math.round(
              ((event.clientX - drag.current.x) / bounds.width) * visibleCount,
            );
            setView((current) => ({
              ...current,
              offset: Math.max(
                0,
                Math.min(
                  candles.length - Math.min(current.count, candles.length),
                  drag.current!.offset + bars,
                ),
              ),
            }));
          }
          const bounds = event.currentTarget.getBoundingClientRect();
          const position =
            ((event.clientX - bounds.left) / bounds.width) * width;
          setHover(
            Math.max(
              0,
              Math.min(
                chart.parsed.length - 1,
                Math.floor(
                  ((position - left) / (width - left - right)) *
                    chart.parsed.length,
                ),
              ),
            ),
          );
        }}
      >
        {[0, 1, 2, 3, 4].map((index) => {
          const y = top + (index * (chart.plotBottom - top)) / 4;
          const value =
            chart.ceiling - (index * (chart.ceiling - chart.floor)) / 4;
          return (
            <g key={index}>
              <line
                x1={left}
                x2={width}
                y1={y}
                y2={y}
                stroke="#2a303a"
                strokeWidth="1"
              />
              <text x={width - 82} y={y - 7} fill="#89919d" fontSize="11">
                {formatPrice(value, precision)}
              </text>
            </g>
          );
        })}
        {[0, 1, 2, 3, 4, 5].map((index) => {
          const itemIndex = Math.min(
            chart.parsed.length - 1,
            Math.floor((index / 5) * (chart.parsed.length - 1)),
          );
          const x = chart.x(itemIndex);
          return (
            <g key={index}>
              <line
                x1={x}
                x2={x}
                y1={top}
                y2={volumeBottom}
                stroke="#242a34"
                strokeWidth="1"
              />
              <text x={x - 19} y={height - 11} fill="#89919d" fontSize="11">
                {new Date(chart.parsed[itemIndex]!.openTime).toLocaleString(
                  "en-US",
                  timeFormat,
                )}
              </text>
            </g>
          );
        })}
        {!referenceLine &&
          chart.parsed.map((item, index) => {
            const x = chart.x(index);
            const color = item.c >= item.o ? "#20b994" : "#f3485d";
            const bodyTop = Math.min(chart.y(item.o), chart.y(item.c));
            const bodyHeight = Math.max(
              1.5,
              Math.abs(chart.y(item.o) - chart.y(item.c)),
            );
            const volumeHeight =
              (item.v / chart.maxVolume) * (volumeBottom - volumeTop);
            return (
              <g key={item.openTime}>
                <line
                  x1={x}
                  x2={x}
                  y1={chart.y(item.h)}
                  y2={chart.y(item.l)}
                  stroke={color}
                  strokeWidth="1.5"
                />
                <rect
                  x={x - chart.candleWidth / 2}
                  y={bodyTop}
                  width={chart.candleWidth}
                  height={bodyHeight}
                  fill={color}
                />
                <rect
                  x={x - chart.candleWidth / 2}
                  y={volumeBottom - volumeHeight}
                  width={chart.candleWidth}
                  height={volumeHeight}
                  fill={color}
                  opacity=".76"
                />
              </g>
            );
          })}
        {referenceLine && (
          <polyline
            points={chart.closeLine}
            fill="none"
            stroke="#1fc297"
            strokeWidth="2"
            vectorEffect="non-scaling-stroke"
          />
        )}
        {chart.ma7 && (
          <polyline
            points={chart.ma7}
            fill="none"
            stroke="#e3ad29"
            strokeWidth="1.5"
          />
        )}
        {chart.ma25 && (
          <polyline
            points={chart.ma25}
            fill="none"
            stroke="#bc6ad9"
            strokeWidth="1.5"
          />
        )}
        {chart.ma99 && (
          <polyline
            points={chart.ma99}
            fill="none"
            stroke="#ad82d6"
            strokeWidth="1.5"
          />
        )}
        {!referenceLine && (
          <line
            x1={left}
            x2={width}
            y1={volumeTop - 10}
            y2={volumeTop - 10}
            stroke="#343b46"
          />
        )}
        <line
          x1={left}
          x2={width - right}
          y1={chart.y(current.c)}
          y2={chart.y(current.c)}
          stroke={priceColor}
          strokeDasharray="5 4"
          opacity=".6"
        />
        <rect
          x={width - right + 2}
          y={chart.y(current.c) - 11}
          width={right - 4}
          height="23"
          rx="3"
          fill={priceColor}
        />
        <text
          x={width - right + 7}
          y={chart.y(current.c) + 5}
          fill="white"
          fontSize="12"
          fontWeight="700"
        >
          {formatPrice(current.c, precision)}
        </text>
        {hover !== null && (
          <line
            x1={chart.x(activeIndex)}
            x2={chart.x(activeIndex)}
            y1={top}
            y2={volumeBottom}
            stroke="#7d8793"
            strokeDasharray="4 4"
          />
        )}
      </svg>
      <div className="chart-legend">
        <span>
          <i className="legend-ma7" />
          MA(7)
        </span>
        <span>
          <i className="legend-ma25" />
          MA(25)
        </span>
        <span>
          <i className="legend-ma99" />
          MA(99)
        </span>
        {!referenceLine && (
          <span>
            <i className="legend-volume" />
            Volume
          </span>
        )}
      </div>
    </div>
  );
}
