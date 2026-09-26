"use client";

import { useEffect, useState } from "react";
import { io } from "socket.io-client";
import type {
  Candle,
  CandleSeries,
  Instrument,
  MarketInterval,
} from "./market-data";

type RealtimeCandle = {
  instrumentId: string;
  interval: MarketInterval;
  sequence: string;
  providerTimestamp: string;
  executionPrice: false;
  executionEligible: false;
  candle: Candle;
};

export type LiveTicker = { price: number; change: number; timestamp: number };

export function connectMarketCandle(
  instrumentId: string,
  interval: MarketInterval,
  onCandle: (event: RealtimeCandle) => void,
  onStatus: (connected: boolean) => void,
  onGap: () => void,
) {
  const endpoint =
    process.env.NEXT_PUBLIC_MARKET_SOCKET_URL ||
    "https://api.zettax.app/market";
  const socket = io(endpoint, {
    transports: ["websocket"],
    autoConnect: false,
    reconnection: true,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 30_000,
    timeout: 8000,
  });
  let accepted = false;
  let lastSequence: bigint | null = null;
  socket.on("market:ready", () => {
    socket.emit(
      "market:subscribe",
      { instrumentId, interval },
      (ack: { ok?: boolean }) => {
        accepted = ack?.ok === true;
        onStatus(accepted);
      },
    );
  });
  socket.on("market:status", (status: { state?: string }) =>
    onStatus(status?.state === "CONNECTED"),
  );
  socket.on("market:candle", (event: RealtimeCandle) => {
    if (
      !accepted ||
      event?.instrumentId !== instrumentId ||
      event.interval !== interval ||
      event.executionPrice !== false ||
      event.executionEligible !== false ||
      !event.candle
    )
      return;
    try {
      const sequence = BigInt(event.sequence);
      if (lastSequence !== null && sequence !== lastSequence + 1n) onGap();
      lastSequence = sequence;
      if (
        Number.isFinite(Number(event.candle.close)) &&
        Number.isFinite(Number(event.candle.high)) &&
        Number.isFinite(Number(event.candle.low))
      )
        onCandle(event);
    } catch {
      onGap();
    }
  });
  socket.on("disconnect", () => {
    accepted = false;
    onStatus(false);
  });
  socket.on("connect_error", () => onStatus(false));
  socket.connect();
  return () => {
    socket.emit("market:unsubscribe");
    socket.disconnect();
    onStatus(false);
  };
}

export function mergeRealtimeCandle(
  current: CandleSeries | undefined,
  event: RealtimeCandle,
): CandleSeries | undefined {
  if (
    !current ||
    current.instrumentId !== event.instrumentId ||
    current.requestedInterval !== event.interval
  )
    return current;
  const candles = current.candles.filter(
    (item) => item.openTime !== event.candle.openTime,
  );
  candles.push(event.candle);
  candles.sort((a, b) => a.openTime.localeCompare(b.openTime));
  return {
    ...current,
    providerTimestamp: event.providerTimestamp,
    candles: candles.slice(-200),
  };
}

export function useCryptoTickers(instruments: Instrument[]) {
  const [tickers, setTickers] = useState<Record<string, LiveTicker>>({});
  const key = instruments
    .filter((item) => item.assetClass === "CRYPTO" && item.quoteAsset === "USD")
    .map((item) => `${item.baseAsset.toLowerCase()}usdt`)
    .sort()
    .join("/");
  useEffect(() => {
    if (!key) return;
    const symbols = new Map(
      instruments
        .filter(
          (item) => item.assetClass === "CRYPTO" && item.quoteAsset === "USD",
        )
        .map((item) => [`${item.baseAsset.toUpperCase()}USDT`, item.id]),
    );
    let socket: WebSocket | null = null;
    let reconnect: ReturnType<typeof setTimeout> | undefined;
    let stopped = false;
    let attempts = 0;
    const connect = () => {
      if (stopped) return;
      let current: WebSocket;
      try {
        current = new WebSocket(
          `wss://stream.binance.com:9443/stream?streams=${key
            .split("/")
            .map((item) => `${item}@miniTicker`)
            .join("/")}`,
        );
      } catch {
        reconnect = setTimeout(
          connect,
          Math.min(30_000, 1000 * 2 ** Math.min(attempts++, 5)),
        );
        return;
      }
      socket = current;
      current.onopen = () => {
        attempts = 0;
      };
      current.onmessage = (message) => {
        if (stopped) return;
        try {
          const payload = JSON.parse(message.data) as {
            data?: { s?: string; c?: string; o?: string; E?: number };
          };
          const data = payload.data;
          const id = data?.s ? symbols.get(data.s) : undefined;
          const price = Number(data?.c);
          const open = Number(data?.o);
          if (
            !id ||
            !Number.isFinite(price) ||
            price <= 0 ||
            !Number.isFinite(open) ||
            open <= 0
          )
            return;
          setTickers((current) => ({
            ...current,
            [id]: {
              price,
              change: ((price - open) / open) * 100,
              timestamp: Number(data?.E) || Date.now(),
            },
          }));
        } catch {
          /* Ignore malformed provider events. */
        }
      };
      current.onclose = () => {
        if (!stopped)
          reconnect = setTimeout(
            connect,
            Math.min(30_000, 1000 * 2 ** Math.min(attempts++, 5)),
          );
      };
      current.onerror = () => current.close();
    };
    connect();
    return () => {
      stopped = true;
      if (reconnect) clearTimeout(reconnect);
      socket?.close();
    };
  }, [key, instruments]);
  return tickers;
}
