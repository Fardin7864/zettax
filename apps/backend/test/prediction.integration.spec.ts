import {
  Prisma,
  AccountMode,
  LedgerDirection,
  LedgerTransactionType,
} from "@prisma/client";
import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { PrismaService } from "../src/database/prisma.service";
import { LedgerService } from "../src/database/ledger.service";
import { OutboxService } from "../src/database/outbox.service";
import { PredictionService } from "../src/prediction/prediction.service";
const suite =
  process.env.RUN_PREDICTION_INTEGRATION === "true" &&
  process.env.DATABASE_URL?.includes("schema=codex_prediction_")
    ? describe
    : describe.skip;
suite("isolated PostgreSQL prediction integrity", () => {
  const prisma = new PrismaService(),
    ledger = new LedgerService();
  const source = "BINANCE_1S_V1:BTCUSDT";
  const prices = {
    at: async (_: unknown, boundary: Date) => ({
      price: new Prisma.Decimal("110"),
      timestamp: new Date(Math.floor(boundary.getTime() / 1000) * 1000 - 1),
      providerId: source,
    }),
  };
  const service = new PredictionService(
    prisma,
    { mode: "DEMO_ONLY" } as never,
    ledger,
    new OutboxService(),
    prices as never,
    {} as never,
    { changed() {}, created() {} } as never,
  );
  let instrumentId: string, userId: string, accountId: string;
  beforeAll(async () => {
    await prisma.$connect();
    await prisma.currency.upsert({
      where: { code: "USD" },
      update: {},
      create: { code: "USD", name: "US Dollar", precision: 2 },
    });
    const instrument = await prisma.instrument.upsert({
      where: { slug: "btc-usd" },
      update: {},
      create: {
        slug: "btc-usd",
        symbol: "BTC/USD",
        name: "Bitcoin",
        assetClass: "CRYPTO",
        baseAsset: "BTC",
        quoteAsset: "USD",
        pricePrecision: 2,
        quantityPrecision: 8,
        demoEnabled: true,
        realEnabled: false,
      },
    });
    instrumentId = instrument.id;
    const user = await prisma.user.create({
      data: {
        email: `prediction-${randomUUID()}@example.invalid`,
        passwordHash: "test-only",
      },
    });
    userId = user.id;
    const account = await prisma.account.create({
      data: { userId, mode: AccountMode.DEMO },
    });
    accountId = account.id;
    await prisma.$transaction(async (tx) => {
      await tx.wallet.create({
        data: { accountId, currencyCode: "USD", availableProjection: "100.00" },
      });
      const accounts = await ledger.ensureAccountLedgerAccounts(
        tx,
        accountId,
        AccountMode.DEMO,
      );
      await ledger.post(tx, {
        type: LedgerTransactionType.DEMO_FUNDING,
        idempotencyKey: `prediction-fixture:${randomUUID()}`,
        description: "Isolated test funds",
        entries: [
          {
            ledgerAccountId: accounts.control,
            direction: LedgerDirection.DEBIT,
            amount: new Prisma.Decimal(100),
          },
          {
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.CREDIT,
            amount: new Prisma.Decimal(100),
          },
        ],
      });
    });
  });
  afterAll(() => prisma.$disconnect());
  async function question(expiry = new Date(Date.now() + 3600000)) {
    return prisma.predictionQuestion.create({
      data: {
        instrumentId,
        condition: "ABOVE",
        targetPrice: "100",
        referencePrice: "100",
        referenceSource: source,
        referenceTimestamp: new Date(),
        expiresAt: expiry,
      },
    });
  }
  async function wallet() {
    return prisma.wallet.findUniqueOrThrow({
      where: { accountId_currencyCode: { accountId, currencyCode: "USD" } },
    });
  }
  it("deduplicates concurrent requests and rejects opposite sides", async () => {
    const q = await question(),
      key = randomUUID();
    const body = {
      accountMode: "DEMO" as const,
      side: "YES" as const,
      stake: "10.00",
    };
    const [a, b] = await Promise.all([
      service.place(userId, q.id, key, body),
      service.place(userId, q.id, key, body),
    ]);
    expect(a).toEqual(b);
    expect(
      await prisma.predictionPosition.count({ where: { questionId: q.id } }),
    ).toBe(1);
    expect((await wallet()).lockedProjection.toFixed(2)).toBe("10.00");
    await expect(
      service.place(userId, q.id, randomUUID(), { ...body, side: "NO" }),
    ).rejects.toMatchObject({ code: "SIDE_LOCKED" });
    await service.cancel(q.id, "Test cancellation");
    expect((await wallet()).availableProjection.toFixed(2)).toBe("100.00");
    await service.cancel(q.id, "Idempotent replay");
    expect((await wallet()).availableProjection.toFixed(2)).toBe("100.00");
  });
  it("concurrent stakes on different questions cannot overdraw a wallet", async () => {
    const [a, b] = await Promise.all([question(), question()]);
    const body = {
      accountMode: "DEMO" as const,
      side: "YES" as const,
      stake: "70.00",
    };
    const results = await Promise.allSettled([
      service.place(userId, a.id, randomUUID(), body),
      service.place(userId, b.id, randomUUID(), body),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect((await wallet()).availableProjection.toFixed(2)).toBe("30.00");
    await service.cancel(a.id, "Test cleanup");
    await service.cancel(b.id, "Test cleanup");
    expect((await wallet()).lockedProjection.toFixed(2)).toBe("0.00");
  });
  it("settles the original expiry once and records a winning position even without opposing stakes", async () => {
    const q = await question();
    await service.place(userId, q.id, randomUUID(), {
      accountMode: "DEMO",
      side: "YES",
      stake: "10.00",
    });
    await prisma.predictionQuestion.update({
      where: { id: q.id },
      data: { expiresAt: new Date(Date.now() - 1000) },
    });
    await Promise.all([
      service.retrySettlement(q.id),
      service.retrySettlement(q.id),
    ]);
    const p = await prisma.predictionPosition.findFirstOrThrow({
      where: { questionId: q.id },
    });
    expect(p.result).toBe("WON");
    expect(p.payoutAmount?.toFixed(2)).toBe("10.00");
    expect(
      await prisma.ledgerTransaction.count({
        where: { idempotencyKey: `prediction-settle:${p.id}` },
      }),
    ).toBe(1);
    expect((await wallet()).availableProjection.toFixed(2)).toBe("100.00");
  });
  it("concurrent question creation reuses the same immutable terms", async () => {
    const key = randomUUID();
    const body = {
      instrumentId: "btc-usd",
      condition: "ABOVE" as const,
      targetPrice: "110",
      expiresAt: new Date(Date.now() + 3600000).toISOString(),
    };
    const [a, b] = await Promise.all([
      service.create(userId, body, key),
      service.create(userId, body, key),
    ]);
    expect(a.id).toBe(b.id);
    expect(
      await prisma.predictionQuestion.count({
        where: { creatorId: userId, clientRequestKey: key },
      }),
    ).toBe(1);
    await expect(
      service.create(userId, { ...body, targetPrice: "109" }, key),
    ).rejects.toMatchObject({ code: "IDEMPOTENCY_KEY_REUSED" });
  });
});
