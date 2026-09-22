import { describe, expect, it } from "vitest";
import { instruments } from "../src/markets/instruments";
import { parseBinanceKline } from "../src/markets/market-realtime.gateway";

const stream = {
  instrument: instruments.find((item) => item.id === "btc-usd")!,
  interval: "1m" as const,
  sourceSymbol: "BTCUSDT",
};

describe("market realtime normalization", () => {
  it("normalizes a Binance kline without granting execution authority", () => {
    const event = parseBinanceKline(
      JSON.stringify({
        e: "kline",
        E: 1_800_000,
        k: {
          t: 1_740_000,
          T: 1_799_999,
          o: "100.00",
          h: "105.00",
          l: "99.00",
          c: "103.00",
          v: "12.50",
          x: false,
        },
      }),
      stream,
      42n,
    );

    expect(event).toMatchObject({
      schemaVersion: 1,
      sequence: "42",
      instrumentId: "btc-usd",
      interval: "1m",
      providerId: "BINANCE_PUBLIC_SPOT",
      sourceSymbol: "BTCUSDT",
      executionPrice: false,
      executionEligible: false,
      final: false,
      candle: {
        open: "100.00",
        high: "105.00",
        low: "99.00",
        close: "103.00",
        volume: "12.50",
      },
    });
  });

  it("rejects malformed or impossible candle messages", () => {
    expect(parseBinanceKline("not-json", stream, 1n)).toBeNull();
    expect(
      parseBinanceKline(
        JSON.stringify({
          e: "kline",
          E: 1_800_000,
          k: {
            t: 1_740_000,
            T: 1_799_999,
            o: "110",
            h: "105",
            l: "99",
            c: "103",
            v: "12",
            x: true,
          },
        }),
        stream,
        2n,
      ),
    ).toBeNull();
  });
});
