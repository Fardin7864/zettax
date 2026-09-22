import { ConfigService } from "@nestjs/config";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MarketDataService } from "../src/markets/market-data.service";
import type { MarketInterval } from "../src/markets/market-data.provider";
import { BinanceMarketDataProvider } from "../src/markets/providers/binance-market-data.provider";
import { FrankfurterMarketDataProvider } from "../src/markets/providers/frankfurter-market-data.provider";
import { TwelveDataMarketDataProvider } from "../src/markets/providers/twelve-data-market-data.provider";

function service(environment: Record<string, string> = {}): MarketDataService {
  const config = new ConfigService(environment);
  return new MarketDataService(
    config,
    new BinanceMarketDataProvider(),
    new FrankfurterMarketDataProvider(),
    new TwelveDataMarketDataProvider(config),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("display market data", () => {
  it.each(["aapl", "msft", "nvda", "spx", "ndx", "xau-usd", "xag-usd"])(
    "serves %s as clearly simulated paper candles in sandbox without a licensed provider", async (id) => {
      const result = await service({ COMPLIANCE_MODE: "SANDBOX" }).candles(id, "1m", 90);
      expect(result).toMatchObject({ providerId: "PRIMEVEST_SANDBOX", freshness: "SIMULATED",
        executionPrice: false, executionEligible: false, isSyntheticOhlc: true });
      expect(result.candles).toHaveLength(90);
      expect(result.candles.every((candle) => Number(candle.low) <= Number(candle.close) && Number(candle.close) <= Number(candle.high))).toBe(true);
    },
  );
  it("does not enable paper candles outside sandbox", async () => {
    await expect(service({ COMPLIANCE_MODE: "PRODUCTION_APPROVED" }).candles("aapl", "1m", 10))
      .rejects.toMatchObject({ code: "MARKET_DATA_KEY_REQUIRED" });
  });
  it("normalizes public crypto candles with non-execution provenance", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(
          JSON.stringify([
            [
              1_788_818_400_000,
              "79000.00",
              "79500.00",
              "78900.00",
              "79200.00",
              "12.5",
              1_788_821_999_999,
            ],
          ]),
          { status: 200 },
        ),
      );
    vi.stubGlobal("fetch", fetchMock);

    const result = await service().candles("btc-usd", "1h", 10);

    expect(result).toMatchObject({
      providerId: "BINANCE_PUBLIC_SPOT",
      provider: "Binance Public Spot",
      sourceSymbol: "BTCUSDT",
      freshness: "DISPLAY_LIVE",
      executionPrice: false,
      executionEligible: false,
      isSyntheticOhlc: false,
    });
    expect(result.candles[0]).toMatchObject({
      open: "79000.00",
      close: "79200.00",
      volume: "12.5",
    });
    expect(String(fetchMock.mock.calls[0]?.[0])).toContain(
      "https://api.binance.com/api/v3/klines?",
    );
  });

  it("uses attributed keyless ECB reference history for forex", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify([
            {
              date: "2026-09-04",
              base: "EUR",
              quote: "USD",
              rate: 1.16,
              providers: [{ key: "ECB" }],
            },
            {
              date: "2026-09-07",
              base: "EUR",
              quote: "USD",
              rate: 1.17,
              providers: ["ECB"],
            },
          ]),
          { status: 200 },
        ),
      ),
    );

    const result = await service().candles("eur-usd", "30m", 10);

    expect(result).toMatchObject({
      providerId: "FRANKFURTER_ECB",
      freshness: "REFERENCE_DAILY",
      requestedInterval: "30m",
      effectiveInterval: "1d",
      isSyntheticOhlc: true,
      executionEligible: false,
    });
    expect(result.candles.at(-1)?.close).toBe("1.17");
  });

  it("keeps Twelve Data credentials out of the URL and normalizes candles", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          values: [
            {
              datetime: "2026-09-08 10:00:00",
              open: "220.10",
              high: "221.00",
              low: "219.50",
              close: "220.80",
              volume: "1000",
            },
          ],
        }),
        { status: 200 },
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const result = await service({
      TWELVE_DATA_API_KEY: "secret-test-key",
      TWELVE_DATA_DISPLAY_LICENSE_APPROVED: "true",
    }).candles("aapl", "1h", 10);

    const [url, options] = fetchMock.mock.calls[0] as [
      string,
      { headers: Record<string, string> },
    ];
    expect(url).not.toContain("secret-test-key");
    expect(options.headers.Authorization).toBe("apikey secret-test-key");
    expect(result).toMatchObject({
      providerId: "TWELVE_DATA",
      freshness: "DELAYED",
      executionEligible: false,
    });
  });

  it("requires both provider credentials and display-rights attestation", async () => {
    await expect(service().candles("aapl", "1h", 10)).rejects.toMatchObject({
      code: "MARKET_DATA_KEY_REQUIRED",
      status: 503,
    });
    await expect(
      service({ TWELVE_DATA_API_KEY: "configured" }).candles("aapl", "1h", 10),
    ).rejects.toMatchObject({
      code: "MARKET_DATA_LICENSE_REQUIRED",
      status: 503,
    });
  });

  it("coalesces identical requests and serves the short-lived cache", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(
          JSON.stringify([
            [1_788_818_400_000, "1", "2", "1", "2", "10", 1_788_821_999_999],
          ]),
          { status: 200 },
        ),
      );
    vi.stubGlobal("fetch", fetchMock);
    const marketData = service();

    await Promise.all([
      marketData.candles("btc-usd", "1h", 10),
      marketData.candles("btc-usd", "1h", 10),
    ]);
    await marketData.candles("btc-usd", "1h", 10);

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("supports weekly/monthly intervals and an exclusive history cursor", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(
          JSON.stringify([
            [1_788_818_400_000, "1", "2", "1", "2", "10", 1_788_821_999_999],
          ]),
          { status: 200 },
        ),
      );
    vi.stubGlobal("fetch", fetchMock);
    const before = "2026-09-08T00:00:00.000Z";

    const result = await service().candles("btc-usd", "1M", 10, before);

    const url = new URL(String(fetchMock.mock.calls[0]?.[0]));
    expect(url.searchParams.get("interval")).toBe("1M");
    expect(url.searchParams.get("endTime")).toBe(
      String(new Date(before).getTime() - 1),
    );
    expect(result.requestedInterval).toBe("1M");
    expect(result.nextCursor).toBeNull();
  });

  it("enforces the configured Twelve Data request budget", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            values: [
              {
                datetime: "2026-09-08 10:00:00",
                open: "1",
                high: "2",
                low: "1",
                close: "2",
              },
            ],
          }),
          { status: 200 },
        ),
      ),
    );
    const marketData = service({
      TWELVE_DATA_API_KEY: "configured",
      TWELVE_DATA_DISPLAY_LICENSE_APPROVED: "true",
      TWELVE_DATA_REQUESTS_PER_MINUTE: "1",
    });
    await marketData.candles("aapl", "1h", 10);

    await expect(marketData.candles("msft", "1h", 10)).rejects.toMatchObject({
      code: "MARKET_DATA_RATE_LIMITED",
      status: 503,
    });
  });

  it("does not expose upstream error bodies", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValue(
          new Response("provider secret diagnostic", { status: 500 }),
        ),
    );

    await expect(service().candles("btc-usd", "1h", 10)).rejects.toMatchObject({
      code: "MARKET_DATA_UNAVAILABLE",
      message: "Display market data is temporarily unavailable.",
    });
  });

  it("rejects unknown instruments, intervals, and unbounded limits", async () => {
    const marketData = service();
    await expect(
      marketData.candles("not-listed", "1h", 10),
    ).rejects.toMatchObject({ code: "INSTRUMENT_NOT_FOUND" });
    await expect(
      marketData.candles("btc-usd", "2m" as MarketInterval, 10),
    ).rejects.toMatchObject({ code: "UNSUPPORTED_INTERVAL" });
    await expect(
      marketData.candles("btc-usd", "1h", 201),
    ).rejects.toMatchObject({ code: "INVALID_CANDLE_LIMIT" });
    await expect(
      marketData.candles("btc-usd", "1h", 10, "2099-01-01T00:00:00.000Z"),
    ).rejects.toMatchObject({ code: "INVALID_CANDLE_CURSOR" });
  });
});
