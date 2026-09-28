import { Prisma } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import { PredictionService } from "../src/prediction/prediction.service";
import { PredictionController } from "../src/prediction/prediction.controller";
import { ApiErrorException } from "../src/http/api-error";

const decimal = (v: string) => new Prisma.Decimal(v);
function fixture() {
  const question = {
    id: "question",
    status: "OPEN",
    expiresAt: new Date(Date.now() + 3600000),
    instrument: { demoEnabled: true },
  };
  const tx = {
    $queryRaw: vi.fn(),
    notification: { create: vi.fn() },
    predictionQuestion: {
      updateMany: vi.fn(),
      findUnique: vi.fn(async () => question),
      update: vi.fn(),
      count: vi.fn(async () => 0),
      create: vi.fn(),
    },
    predictionPosition: {
      findUnique: vi.fn(async () => null),
      findFirst: vi.fn(async () => null),
      count: vi.fn(async () => 0),
      create: vi.fn(async ({ data }) => ({
        ...data,
        id: "position",
        payoutAmount: null,
        result: "PENDING",
        createdAt: new Date(),
        settledAt: null,
      })),
      update: vi.fn(),
    },
    user: { findUnique: vi.fn(async () => ({ tradingEnabled: true })) },
    account: { findUnique: vi.fn(async () => ({ id: "account" })) },
    wallet: { update: vi.fn() },
    auditLog: { create: vi.fn() },
  };
  const prisma = {
    $transaction: vi.fn(async (work) => work(tx)),
    instrument: { findUnique: vi.fn() },
    predictionQuestion: {
      findMany: vi.fn(async () => []),
      count: vi.fn(async () => 0),
      findUnique: vi.fn(async () => null),
    },
  };
  const ledger = {
    requireOwnedAccount: vi.fn(),
    lockWallet: vi.fn(async () => ({
      id: "wallet",
      availableProjection: decimal("100"),
      lockedProjection: decimal("0"),
    })),
    ensureAccountLedgerAccounts: vi.fn(async () => ({
      available: "available",
      locked: "locked",
    })),
    post: vi.fn(),
  };
  const outbox = { enqueueAccount: vi.fn() };
  const prices = {
    at: vi.fn(async (_instrument, boundary) => ({
      price: decimal("100"),
      providerId: "BINANCE_1S_V1:BTCUSDT",
      timestamp: new Date(boundary.getTime() - 1),
    })),
  };
  const service = new PredictionService(
    prisma as never,
    { mode: "DEMO_ONLY" } as never,
    ledger as never,
    outbox as never,
    prices as never,
    {} as never,
    { changed: vi.fn(), created: vi.fn() } as never,
  );
  return { service, tx, prisma, ledger, outbox, prices, question };
}
const stake = {
  accountMode: "DEMO" as const,
  side: "YES" as const,
  stake: "10.00",
};
describe("prediction experience safeguards", () => {
  it("delays a missing observation and refunds after the documented 24-hour timeout", async () => {
    const f = fixture();
    f.prisma.predictionQuestion.findMany.mockResolvedValue([
      { id: "q" },
    ] as never);
    f.prisma.predictionQuestion.findUnique.mockResolvedValue({
      expiresAt: new Date(Date.now() - 1000),
    } as never);
    Object.assign(f.prisma.predictionQuestion, { updateMany: vi.fn() });
    const settle = vi
      .spyOn(
        f.service as unknown as { settleOne(id: string): Promise<boolean> },
        "settleOne",
      )
      .mockRejectedValue(
        new ApiErrorException("CONTRACT_PRICE_UNAVAILABLE", "Unavailable", 503),
      );
    const cancel = vi
      .spyOn(f.service, "cancel")
      .mockResolvedValue({ id: "q", refunded: true });
    await f.service.settleDueBatch();
    expect(cancel).not.toHaveBeenCalled();
    expect(settle).toHaveBeenCalled();
    f.prisma.predictionQuestion.findUnique.mockResolvedValue({
      expiresAt: new Date(Date.now() - 25 * 3600000),
    } as never);
    await f.service.settleDueBatch();
    expect(cancel).toHaveBeenCalledWith(
      "q",
      expect.stringContaining("24 hours"),
    );
  });
  it("locks stake and records a durable personal event", async () => {
    const f = fixture();
    await f.service.place("user", "question", "stake-key", stake);
    expect(f.tx.wallet.update).toHaveBeenCalledWith({
      where: { id: "wallet" },
      data: {
        availableProjection: { decrement: decimal("10") },
        lockedProjection: { increment: decimal("10") },
      },
    });
    expect(f.tx.predictionQuestion.update).toHaveBeenCalledWith({
      where: { id: "question" },
      data: {
        yesDemoPool: { increment: decimal("10") },
        participantCount: { increment: 1 },
      },
    });
    expect(f.ledger.post).toHaveBeenCalledOnce();
    expect(f.outbox.enqueueAccount).toHaveBeenCalledOnce();
  });
  it("replays a successful command without locking or posting again", async () => {
    const f = fixture();
    f.tx.predictionPosition.findUnique.mockResolvedValue({
      ...stake,
      mode: "DEMO",
      stake: decimal("10"),
      questionId: "question",
      id: "position",
      payoutAmount: null,
      createdAt: new Date(),
      settledAt: null,
      result: "PENDING",
    } as never);
    await f.service.place("user", "question", "stake-key", stake);
    expect(f.ledger.lockWallet).not.toHaveBeenCalled();
    expect(f.tx.predictionPosition.create).not.toHaveBeenCalled();
  });
  it("rejects changed terms on an existing idempotency key", async () => {
    const f = fixture();
    f.tx.predictionPosition.findUnique.mockResolvedValue({
      mode: "DEMO",
      stake: decimal("10"),
      questionId: "question",
      side: "NO",
    } as never);
    await expect(
      f.service.place("user", "question", "stake-key", stake),
    ).rejects.toMatchObject({ code: "IDEMPOTENCY_KEY_REUSED" });
    expect(f.ledger.lockWallet).not.toHaveBeenCalled();
  });
  it("prevents choosing both sides while allowing same-side topups", async () => {
    const f = fixture();
    f.tx.predictionPosition.findFirst.mockResolvedValue({
      side: "NO",
    } as never);
    await expect(
      f.service.place("user", "question", "stake-key", stake),
    ).rejects.toMatchObject({ code: "SIDE_LOCKED" });
    expect(f.tx.wallet.update).not.toHaveBeenCalled();
    f.tx.predictionPosition.findFirst.mockResolvedValue({
      side: "YES",
    } as never);
    await f.service.place("user", "question", "stake-key", stake);
    expect(f.tx.predictionQuestion.update).toHaveBeenCalledWith({
      where: { id: "question" },
      data: { yesDemoPool: { increment: decimal("10") } },
    });
  });
  it("rejects expired questions, insufficient funds and restricted accounts before mutation", async () => {
    const f = fixture();
    f.question.expiresAt = new Date(0);
    await expect(
      f.service.place("user", "question", "stake-key", stake),
    ).rejects.toMatchObject({ code: "QUESTION_EXPIRED" });
    f.question.expiresAt = new Date(Date.now() + 3600000);
    f.ledger.lockWallet.mockResolvedValue({
      id: "wallet",
      availableProjection: decimal("1"),
      lockedProjection: decimal("0"),
    });
    await expect(
      f.service.place("user", "question", "stake-key", stake),
    ).rejects.toMatchObject({ code: "INSUFFICIENT_FUNDS" });
    f.tx.user.findUnique.mockResolvedValue({ tradingEnabled: false });
    await expect(
      f.service.place("user", "question", "stake-key", stake),
    ).rejects.toMatchObject({ code: "ACCOUNT_RESTRICTED" });
    expect(f.tx.wallet.update).not.toHaveBeenCalled();
  });
  it("paginates results and translates awaiting-price state", async () => {
    const f = fixture();
    await f.service.list({ status: "CLOSED", search: "BTC", sort: "ENDING" });
    expect(f.prisma.predictionQuestion.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        take: 21,
        where: expect.objectContaining({
          status: "OPEN",
          expiresAt: { lte: expect.any(Date) },
        }),
      }),
    );
  });
  it("uses verified historical anchors to generate three objective templates", async () => {
    const f = fixture();
    f.prisma.instrument.findUnique.mockImplementation(async ({ where }) =>
      where.slug === "btc-usd"
        ? {
            id: "btc",
            slug: "btc-usd",
            assetClass: "CRYPTO",
            demoEnabled: true,
            pricePrecision: 2,
          }
        : null,
    );
    const create = vi
      .spyOn(f.service, "create")
      .mockResolvedValue({ id: "q" } as never);
    expect(await f.service.ensurePlatformQuestions()).toEqual({ created: 3 });
    expect(create).toHaveBeenCalledTimes(3);
    const calls = create.mock.calls;
    expect(calls.map((call) => call[3]?.context.lookbackHours)).toEqual([
      0, 1, 24,
    ]);
    for (const call of calls) {
      expect(call[0]).toBeNull();
      expect(call[1].targetPrice).toBe("100.00");
      expect(Date.parse(call[1].expiresAt)).toBeGreaterThan(Date.now());
      expect(call[3]?.context.kind).toBe("HISTORICAL_PRICE_ANCHOR");
    }
  });
  it("does not invent defaults when historical prices cannot be verified", async () => {
    const f = fixture();
    f.prisma.instrument.findUnique.mockResolvedValue({
      id: "btc",
      assetClass: "CRYPTO",
      demoEnabled: true,
      pricePrecision: 2,
    });
    f.prices.at.mockRejectedValue(
      new ApiErrorException("CONTRACT_PRICE_UNAVAILABLE", "Unavailable", 503),
    );
    const create = vi.spyOn(f.service, "create");
    expect(await f.service.ensurePlatformQuestions()).toEqual({ created: 0 });
    expect(create).not.toHaveBeenCalled();
  });
  it("does not regenerate active templates or cancelled slots", async () => {
    const f = fixture();
    f.prisma.instrument.findUnique.mockResolvedValue({
      id: "btc",
      assetClass: "CRYPTO",
      demoEnabled: true,
    });
    f.prisma.predictionQuestion.count.mockResolvedValue(1);
    const create = vi.spyOn(f.service, "create");
    await f.service.ensurePlatformQuestions();
    expect(create).not.toHaveBeenCalled();
    f.prisma.predictionQuestion.count.mockResolvedValue(0);
    f.prisma.predictionQuestion.findUnique.mockResolvedValue({
      id: "cancelled",
    } as never);
    await f.service.ensurePlatformQuestions();
    expect(create).not.toHaveBeenCalled();
  });
  it("protects admin actions with permissions", async () => {
    const cancel = vi.fn();
    const controller = new PredictionController({ cancel } as never);
    await expect(
      controller.cancel({ user: { permissions: [] } } as never, "q", {
        reason: "test",
      }),
    ).rejects.toMatchObject({ code: "ADMIN_PERMISSION_REQUIRED" });
    expect(cancel).not.toHaveBeenCalled();
  });
  it("fully refunds each pending stake and makes cancellation replay-safe", async () => {
    const f = fixture();
    const position = {
      id: "p",
      accountId: "a",
      userId: "u",
      mode: "DEMO",
      stake: decimal("10"),
      result: "PENDING",
    };
    f.tx.predictionQuestion.findUnique.mockResolvedValue({
      ...f.question,
      positions: [position],
    } as never);
    f.ledger.lockWallet.mockResolvedValue({
      id: "wallet",
      availableProjection: decimal("90"),
      lockedProjection: decimal("10"),
    });
    f.tx.predictionPosition.update.mockResolvedValue({
      ...position,
      questionId: "q",
      side: "YES",
      createdAt: new Date(),
      settledAt: new Date(),
      payoutAmount: decimal("10"),
      result: "REFUNDED",
    } as never);
    await f.service.cancel("q", "Source outage");
    expect(f.tx.wallet.update).toHaveBeenCalledWith({
      where: { id: "wallet" },
      data: {
        lockedProjection: { decrement: decimal("10") },
        availableProjection: { increment: decimal("10") },
      },
    });
    expect(f.tx.auditLog.create).toHaveBeenCalledOnce();
    f.tx.predictionQuestion.findUnique.mockResolvedValue({
      status: "CANCELLED",
    } as never);
    await f.service.cancel("q", "Source outage");
    expect(f.tx.wallet.update).toHaveBeenCalledOnce();
  });
});
