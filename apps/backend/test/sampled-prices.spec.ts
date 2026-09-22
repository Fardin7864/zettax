import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { describe, expect, it, vi, afterEach } from "vitest";
import { SampledPriceService } from "../src/markets/sampled-price.service";
import { PrismaService } from "../src/database/prisma.service";
import { instruments } from "../src/markets/instruments";

afterEach(() => vi.unstubAllGlobals());
function setup(config: Record<string, string> = {}) {
  const rows: Array<{ id: bigint; instrumentSlug: string; price: Prisma.Decimal; sampledAt: Date; provider: string }> = [];
  const prisma = { sampledPrice: {
    deleteMany: vi.fn(async ({ where }) => { const old = rows.filter((row) => row.sampledAt <= where.sampledAt.lte); for (const row of old) rows.splice(rows.indexOf(row), 1); return { count: old.length }; }),
    findFirst: vi.fn(async ({ where }) => rows.find((row) => row.instrumentSlug === where.instrumentSlug && row.sampledAt >= where.sampledAt.gte) ?? null),
    create: vi.fn(async ({ data }) => { const row = { id: BigInt(rows.length + 1), ...data }; rows.push(row); return row; }),
    findMany: vi.fn(async ({ where, take }) => rows.filter((row) => row.instrumentSlug === where.instrumentSlug && row.sampledAt > where.sampledAt.gt && (!where.sampledAt.lt || row.sampledAt < where.sampledAt.lt)).sort((a, b) => b.sampledAt.getTime() - a.sampledAt.getTime()).slice(0, take)),
  } };
  return { service: new SampledPriceService(prisma as unknown as PrismaService, new ConfigService(config)), rows, prisma };
}
describe("price-only API snapshots", () => {
  it("never calls the external API without both key and external-display approval", async () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    const { service, prisma } = setup({ TWELVE_DATA_API_KEY: "test-key" });
    await service.poll(new Date("2026-09-18T02:15:00Z"));
    expect(fetcher).not.toHaveBeenCalled();
    expect(prisma.sampledPrice.deleteMany).toHaveBeenCalled();
  });
  it("samples seven non-crypto symbols once per 15-minute bucket and deletes old rows", async () => {
    const fetcher = vi.fn().mockImplementation(async () => new Response(JSON.stringify({ price: "238.47" }), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);
    const { service, rows, prisma } = setup({ TWELVE_DATA_API_KEY: "test-key", TWELVE_DATA_EXTERNAL_DISPLAY_APPROVED: "true" });
    const now = new Date();
    rows.push({ id: 100n, instrumentSlug: "aapl", price: new Prisma.Decimal(1), sampledAt: new Date(now.getTime() - 31 * 24 * 60 * 60_000), provider: "old" });
    await service.poll(now); await service.poll(new Date(now.getTime() + 60_000));
    expect(fetcher).toHaveBeenCalledTimes(7);
    expect(rows).toHaveLength(7);
    expect(rows.some((row) => row.instrumentSlug === "btc-usd")).toBe(false);
    expect(String(fetcher.mock.calls[0]?.[0])).not.toContain("test-key");
    expect(fetcher.mock.calls[0]?.[1].headers.Authorization).toBe("apikey test-key");
    expect(prisma.sampledPrice.create).toHaveBeenCalledTimes(7);
    const series = await service.candles(instruments.find((item) => item.id === "aapl")!, "1m", 90);
    expect(series).toMatchObject({ providerId: "TWELVE_DATA_PRICE", freshness: "SAMPLED", effectiveInterval: "15m", isSyntheticOhlc: true });
    expect(series.candles[0]?.close).toBe("238.47");
  });
  it("aggregates only saved samples into the selected interval and excludes old history", async () => {
    const { service, rows } = setup({ TWELVE_DATA_API_KEY: "test-key", TWELVE_DATA_EXTERNAL_DISPLAY_APPROVED: "true" });
    const now = Date.now();
    const hour = Math.floor(now / 3_600_000) * 3_600_000;
    rows.push({ id: 1n, instrumentSlug: "aapl", price: new Prisma.Decimal("100"), sampledAt: new Date(hour + 1_000), provider: "TWELVE_DATA_PRICE" });
    rows.push({ id: 2n, instrumentSlug: "aapl", price: new Prisma.Decimal("103"), sampledAt: new Date(hour + 901_000), provider: "TWELVE_DATA_PRICE" });
    rows.push({ id: 3n, instrumentSlug: "aapl", price: new Prisma.Decimal("101"), sampledAt: new Date(hour + 1_801_000), provider: "TWELVE_DATA_PRICE" });
    rows.push({ id: 4n, instrumentSlug: "aapl", price: new Prisma.Decimal("999"), sampledAt: new Date(now - 31 * 24 * 60 * 60_000), provider: "old" });
    const series = await service.candles(instruments.find((item) => item.id === "aapl")!, "1h", 90);
    expect(series.candles).toHaveLength(1);
    expect(series.candles[0]).toMatchObject({ open: "100", high: "103", low: "100", close: "101" });
  });
});
