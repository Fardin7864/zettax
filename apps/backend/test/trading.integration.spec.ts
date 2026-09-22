import { ConfigService } from "@nestjs/config";
import {
  AccountMode,
  ActorType,
  ContractDirection,
  LedgerDirection,
  LedgerTransactionType,
  OrderSide,
  Prisma,
} from "@prisma/client";
import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { AccountsService } from "../src/accounts/accounts.service";
import { ComplianceService } from "../src/compliance/compliance.service";
import { IdempotencyService } from "../src/database/idempotency.service";
import { LedgerService } from "../src/database/ledger.service";
import { OutboxService } from "../src/database/outbox.service";
import { PrismaService } from "../src/database/prisma.service";
import { DemoPriceService } from "../src/trading/demo-price.service";
import { ExecutionProviderService } from "../src/trading/execution-provider.service";
import { MockExecutionProvider } from "../src/trading/mock-execution.provider";
import type { CreateOrderDto } from "../src/trading/trading.dto";
import { TradingService } from "../src/trading/trading.service";
import { TimedContractsService } from "../src/timed-contracts/timed-contracts.service";
import { ContractPriceService } from "../src/timed-contracts/contract-price.service";

const enabled = process.env.RUN_DATABASE_INTEGRATION === "true";
const suite = enabled ? describe : describe.skip;

type TestUser = {
  userId: string;
  demoAccountId: string;
  realAccountId: string;
};

suite("PostgreSQL account and demo trading integrity", () => {
  const prisma = new PrismaService();
  const ledger = new LedgerService();
  const idempotency = new IdempotencyService();
  const config = new ConfigService({
    COMPLIANCE_MODE: "DEMO_ONLY",
    ENABLE_REAL_TRADING: "false",
    EXECUTION_PROVIDER: "MOCK",
  });
  const trading = new TradingService(
    prisma,
    ledger,
    idempotency,
    new OutboxService(),
    new ExecutionProviderService(
      config,
      new ComplianceService(config),
      new MockExecutionProvider(),
    ),
    new DemoPriceService(),
    new ComplianceService(config),
  );
  const accounts = new AccountsService(
    prisma,
    config,
    ledger,
    idempotency,
    new OutboxService(),
  );
  const timedContracts = new TimedContractsService(
    prisma,
    new ComplianceService(config),
    ledger,
    idempotency,
    new OutboxService(),
    new DemoPriceService(),
  );
  let funded: TestUser;
  let isolated: TestUser;
  let underfunded: TestUser;
  let timedUser: TestUser;

  beforeAll(async () => {
    await prisma.$connect();
    const instrument = await prisma.instrument.findUnique({
      where: { slug: "btc-usd" },
    });
    if (!instrument) {
      throw new Error("Seeded btc-usd instrument is required for this suite");
    }
    funded = await provisionUser("50000.00");
    isolated = await provisionUser("25000.00");
    underfunded = await provisionUser("50.00");
    timedUser = await provisionUser("10000.00");
  });

  afterAll(() => prisma.$disconnect());

  it("deduplicates concurrent demo resets without double-posting", async () => {
    const key = `test-reset:${randomUUID()}`;
    const [first, second] = await Promise.all([
      accounts.resetDemo(isolated.userId, key),
      accounts.resetDemo(isolated.userId, key),
    ]);
    expect(second).toEqual(first);
    expect(first.available).toBe("100000.00");
    expect(
      await prisma.ledgerTransaction.count({
        where: { idempotencyKey: `demo-reset:${isolated.userId}:${key}` },
      }),
    ).toBe(1);
  });

  it("deduplicates concurrent demo order commands without double-locking funds", async () => {
    const body = orderBody("0.1");
    const key = `test-order:${randomUUID()}`;
    const availableBefore = await available(funded.demoAccountId);

    const [first, second] = await Promise.all([
      trading.createOrder(funded.userId, key, body),
      trading.createOrder(funded.userId, key, body),
    ]);

    expect(second).toEqual(first);
    const [orderCount, positionCount, commandCount, wallet] = await Promise.all(
      [
        prisma.order.count({
          where: {
            accountId: funded.demoAccountId,
            clientOrderId: body.clientOrderId,
          },
        }),
        prisma.position.count({
          where: {
            accountId: funded.demoAccountId,
            id: String(first.positionId),
          },
        }),
        prisma.idempotencyCommand.count({
          where: {
            actorType: ActorType.USER,
            actorId: funded.userId,
            operation: "ORDER_CREATE",
            key,
          },
        }),
        prisma.wallet.findUniqueOrThrow({
          where: {
            accountId_currencyCode: {
              accountId: funded.demoAccountId,
              currencyCode: "BDT",
            },
          },
        }),
      ],
    );
    expect(orderCount).toBe(1);
    expect(positionCount).toBe(1);
    expect(commandCount).toBe(1);
    expect(
      wallet.availableProjection
        .plus(wallet.lockedProjection)
        .equals(availableBefore),
    ).toBe(true);
    const accountEvent = await prisma.accountEvent.findFirst({
      where: { userId: funded.userId, eventType: "order.filled" },
      orderBy: { sequence: "desc" },
    });
    expect(accountEvent?.payload).toMatchObject({ id: first.id });
    expect(accountEvent?.sequence).toBeGreaterThan(0n);
  });

  it("keeps wallets and positions isolated between users", async () => {
    const isolatedBefore = await available(isolated.demoAccountId);
    const opened = await trading.createOrder(
      funded.userId,
      `test-isolation:${randomUUID()}`,
      orderBody("0.05"),
    );

    expect(
      (await available(isolated.demoAccountId)).equals(isolatedBefore),
    ).toBe(true);
    await expect(
      trading.closePosition(
        isolated.userId,
        String(opened.positionId),
        `test-foreign-close:${randomUUID()}`,
      ),
    ).rejects.toMatchObject({ code: "POSITION_NOT_FOUND" });
    expect(
      (await available(isolated.demoAccountId)).equals(isolatedBefore),
    ).toBe(true);
  });

  it("settles a concurrently closed position once and replays the winner", async () => {
    const opened = await trading.createOrder(
      funded.userId,
      `test-close-open:${randomUUID()}`,
      orderBody("0.02"),
    );
    const closeKeys = [
      `test-close:${randomUUID()}`,
      `test-close:${randomUUID()}`,
    ];
    const results = await Promise.allSettled(
      closeKeys.map((closeKey) =>
        trading.closePosition(
          funded.userId,
          String(opened.positionId),
          closeKey,
        ),
      ),
    );
    const winnerIndex = results.findIndex(
      (result) => result.status === "fulfilled",
    );
    const loser = results.find((result) => result.status === "rejected");
    expect(
      results.filter((result) => result.status === "fulfilled"),
    ).toHaveLength(1);
    expect(loser).toMatchObject({
      reason: { code: "POSITION_ALREADY_CLOSED" },
    });
    const winner = results[winnerIndex];
    const winnerKey = closeKeys[winnerIndex];
    if (winner?.status !== "fulfilled" || !winnerKey) {
      throw new Error("Close winner missing");
    }
    const replay = await trading.closePosition(
      funded.userId,
      String(opened.positionId),
      winnerKey,
    );
    expect(replay).toEqual(winner.value);
    expect(
      await prisma.ledgerTransaction.count({
        where: {
          idempotencyKey: `position-close:${String(opened.positionId)}`,
        },
      }),
    ).toBe(1);
    const closingOrders = await prisma.order.findMany({
      where: {
        accountId: funded.demoAccountId,
        clientOrderId: `position-close:${String(opened.positionId)}`,
      },
      include: { executions: true },
    });
    expect(closingOrders).toHaveLength(1);
    expect(closingOrders[0]?.side).toBe(OrderSide.SELL);
    expect(closingOrders[0]?.executions).toHaveLength(1);
  });

  it("rejects insufficient funds without leaving command or trading artifacts", async () => {
    const body = orderBody("0.001");
    const key = `test-insufficient:${randomUUID()}`;
    await expect(
      trading.createOrder(underfunded.userId, key, body),
    ).rejects.toMatchObject({ code: "INSUFFICIENT_FUNDS" });
    expect(
      await prisma.order.count({
        where: {
          accountId: underfunded.demoAccountId,
          clientOrderId: body.clientOrderId,
        },
      }),
    ).toBe(0);
    expect(
      await prisma.idempotencyCommand.count({
        where: {
          actorId: underfunded.userId,
          operation: "ORDER_CREATE",
          key,
        },
      }),
    ).toBe(0);
    expect((await available(underfunded.demoAccountId)).equals("50.00")).toBe(
      true,
    );
  });

  it("fails REAL orders closed before creating any command or financial record", async () => {
    const body = { ...orderBody("0.001"), accountMode: AccountMode.REAL };
    const key = `test-real:${randomUUID()}`;
    await expect(
      trading.createOrder(funded.userId, key, body),
    ).rejects.toMatchObject({
      code: "REAL_TRADING_NOT_APPROVED",
    });
    expect(
      await prisma.order.count({
        where: {
          accountId: funded.realAccountId,
          clientOrderId: body.clientOrderId,
        },
      }),
    ).toBe(0);
    expect(
      await prisma.idempotencyCommand.count({
        where: { actorId: funded.userId, operation: "ORDER_CREATE", key },
      }),
    ).toBe(0);
  });

  it("creates and settles each server-timed demo contract exactly once", async () => {
    const key = `test-timed:${randomUUID()}`;
    const lockedBefore = await prisma.wallet.findUniqueOrThrow({
      where: {
        accountId_currencyCode: {
          accountId: timedUser.demoAccountId,
          currencyCode: "BDT",
        },
      },
      select: { lockedProjection: true },
    });
    const created = await timedContracts.create(timedUser.userId, key, {
      accountMode: AccountMode.DEMO,
      instrumentId: "btc-usd",
      direction: ContractDirection.UP,
      investmentAmount: "100.00",
      expectedProfitFeeRate: "0",
      durationSeconds: 30,
    });
    const forcedNow = Date.now();
    await prisma.timedContract.update({
      where: { id: created.id },
      data: {
        entryTimestamp: new Date(forcedNow - 60_000),
        expiryTimestamp: new Date(forcedNow - 30_000),
      },
    });
    await Promise.all([
      timedContracts.settleDueBatch(),
      timedContracts.settleDueBatch(),
    ]);
    const [contract, settlementCount, journalCount, wallet] = await Promise.all(
      [
        prisma.timedContract.findUniqueOrThrow({ where: { id: created.id } }),
        prisma.timedContractSettlement.count({
          where: { contractId: created.id },
        }),
        prisma.ledgerTransaction.count({
          where: { idempotencyKey: `timed-settle:${created.id}` },
        }),
        prisma.wallet.findUniqueOrThrow({
          where: {
            accountId_currencyCode: {
              accountId: timedUser.demoAccountId,
              currencyCode: "BDT",
            },
          },
        }),
      ],
    );
    expect(contract.result).not.toBe("PENDING");
    expect(settlementCount).toBe(1);
    expect(journalCount).toBe(1);
    expect(wallet.lockedProjection.equals(lockedBefore.lockedProjection)).toBe(
      true,
    );
    expect(
      await prisma.accountEvent.count({
        where: {
          userId: timedUser.userId,
          eventType: {
            in: ["timed_contract.created", "timed_contract.settled"],
          },
        },
      }),
    ).toBe(2);
  });

  it.each([
    ["UP", "102", "1020.00"],
    ["UP", "98", "980.00"],
    ["DOWN", "102", "980.00"],
    ["DOWN", "98", "1020.00"],
    ["DOWN", "250", "0.00"],
    ["UP", "1000", "10000.00"],
    ["UP", "100", "1000.00"],
  ])(
    "posts balanced proportional %s settlement at %s",
    async (direction, expiry, payout) => {
      const user = await provisionUser("2000.00");
      let price = "100";
      const source = {
        at: vi.fn((_instrument: unknown, boundary: Date) =>
          Promise.resolve({
            price: new Prisma.Decimal(price),
            timestamp: new Date(
              Math.floor(boundary.getTime() / 1000) * 1000 - 1,
            ),
            providerId: "BINANCE_1S_V1:BTCUSDT",
          }),
        ),
      } as unknown as ContractPriceService;
      const service = new TimedContractsService(
        prisma,
        new ComplianceService(config),
        ledger,
        idempotency,
        new OutboxService(),
        new DemoPriceService(),
        source,
      );
      const body = {
        accountMode: AccountMode.DEMO,
        instrumentId: "btc-usd",
        direction: direction as ContractDirection,
        investmentAmount: "1000.00",
        expectedProfitFeeRate: "0",
        durationSeconds: 30,
      };
      const key = randomUUID();
      const [created, duplicate] = await Promise.all([
        service.create(user.userId, key, body),
        service.create(user.userId, key, body),
      ]);
      expect(duplicate.id).toBe(created.id);
      price = expiry;
      await prisma.timedContract.update({
        where: { id: created.id },
        data: {
          entryTimestamp: new Date(Date.now() - 60000),
          expiryTimestamp: new Date(Date.now() - 1000),
        },
      });
      await Promise.all([service.settleDueBatch(), service.settleDueBatch()]);
      const settlement = await prisma.timedContractSettlement.findUniqueOrThrow(
        { where: { contractId: created.id } },
      );
      expect(settlement.payoutAmount.toFixed(2)).toBe(payout);
      const wallet = await prisma.wallet.findUniqueOrThrow({
        where: {
          accountId_currencyCode: {
            accountId: user.demoAccountId,
            currencyCode: "BDT",
          },
        },
      });
      expect(wallet.lockedProjection.toFixed(2)).toBe("0.00");
      expect(wallet.availableProjection.toFixed(2)).toBe(
        new Prisma.Decimal(1000).plus(payout).toFixed(2),
      );
      expect(
        await prisma.ledgerTransaction.count({
          where: { idempotencyKey: `timed-settle:${created.id}` },
        }),
      ).toBe(1);
    },
  );

  it("retains the accepted fee, charges profit only, and rejects outdated fee review", async () => {
    const user = await provisionUser("2000.00");
    let price = "100";
    const source = {
      at: (_instrument: unknown, boundary: Date) =>
        Promise.resolve({
          price: new Prisma.Decimal(price),
          timestamp: boundary,
          providerId: "BINANCE_1S_V1:BTCUSDT",
        }),
    } as ContractPriceService;
    const service = new TimedContractsService(
      prisma,
      new ComplianceService(config),
      ledger,
      idempotency,
      new OutboxService(),
      new DemoPriceService(),
      source,
    );
    const body = {
      accountMode: AccountMode.DEMO,
      instrumentId: "btc-usd",
      direction: ContractDirection.UP,
      investmentAmount: "1000.00",
      expectedProfitFeeRate: "0.1",
      durationSeconds: 30,
    };
    await prisma.systemConfig.upsert({
      where: { key: "trading.profitFeeRate" },
      create: { key: "trading.profitFeeRate", value: "0.1" },
      update: { value: "0.1" },
    });
    try {
      await expect(
        service.create(user.userId, randomUUID(), {
          ...body,
          expectedProfitFeeRate: "0",
        }),
      ).rejects.toMatchObject({ code: "TRADING_TERMS_CHANGED" });
      const created = await service.create(user.userId, randomUUID(), body);
      await prisma.systemConfig.update({
        where: { key: "trading.profitFeeRate" },
        data: { value: "0.5" },
      });
      price = "102";
      await prisma.timedContract.update({
        where: { id: created.id },
        data: {
          entryTimestamp: new Date(Date.now() - 60000),
          expiryTimestamp: new Date(Date.now() - 1000),
        },
      });
      await service.settleDueBatch();
      const settlement = await prisma.timedContractSettlement.findUniqueOrThrow(
        { where: { contractId: created.id } },
      );
      expect(settlement.payoutAmount.toFixed(2)).toBe("1018.00");
      expect(settlement.feeAmount.toFixed(2)).toBe("2.00");
    } finally {
      await prisma.systemConfig.update({
        where: { key: "trading.profitFeeRate" },
        data: { value: "0" },
      });
    }
  });

  it("keeps funds locked during missing expiry data and recovers the original timestamp after worker restart", async () => {
    const user = await provisionUser("2000.00");
    let offline = false;
    const observations: Date[] = [];
    const source = {
      at: vi.fn((_instrument: unknown, boundary: Date) => {
        observations.push(boundary);
        if (offline)
          return Promise.reject(new Error("Missing original observation"));
        return Promise.resolve({
          price: new Prisma.Decimal("100"),
          timestamp: boundary,
          providerId: "BINANCE_1S_V1:BTCUSDT",
        });
      }),
    } as unknown as ContractPriceService;
    const worker = () =>
      new TimedContractsService(
        prisma,
        new ComplianceService(config),
        ledger,
        idempotency,
        new OutboxService(),
        new DemoPriceService(),
        source,
      );
    const service = worker();
    const body = {
      accountMode: AccountMode.DEMO,
      instrumentId: "btc-usd",
      direction: ContractDirection.DOWN,
      investmentAmount: "1000.00",
      expectedProfitFeeRate: "0",
      durationSeconds: 31536000,
    };
    const key = randomUUID();
    const created = await service.create(user.userId, key, body);
    expect(
      new Date(created.expiryTimestamp).getTime() -
        new Date(created.entryTimestamp).getTime(),
    ).toBe(31536000000);
    offline = true;
    expect((await service.create(user.userId, key, body)).id).toBe(created.id);
    await expect(
      service.create(user.userId, key, {
        ...body,
        investmentAmount: "1001.00",
      }),
    ).rejects.toMatchObject({ code: "IDEMPOTENCY_KEY_REUSED" });
    const expiry = new Date(Date.now() - 10000);
    await prisma.timedContract.update({
      where: { id: created.id },
      data: {
        entryTimestamp: new Date(Date.now() - 60000),
        expiryTimestamp: expiry,
      },
    });
    await service.settleDueBatch();
    expect(
      await prisma.timedContractSettlement.count({
        where: { contractId: created.id },
      }),
    ).toBe(0);
    const wallet = await prisma.wallet.findUniqueOrThrow({
      where: {
        accountId_currencyCode: {
          accountId: user.demoAccountId,
          currencyCode: "BDT",
        },
      },
    });
    expect(wallet.lockedProjection.toFixed(2)).toBe("1000.00");
    offline = false;
    await worker().settleDueBatch();
    expect(observations.at(-1)?.getTime()).toBe(expiry.getTime());
    expect(
      await prisma.timedContractSettlement.count({
        where: { contractId: created.id },
      }),
    ).toBe(1);
  });

  it("paginates long-lived pending contracts and rejects stakes beyond available funds", async () => {
    const user = await provisionUser("20.00");
    const body = {
      accountMode: AccountMode.DEMO,
      instrumentId: "btc-usd",
      direction: ContractDirection.UP,
      investmentAmount: "10.00",
      expectedProfitFeeRate: "0",
      durationSeconds: 31536000,
    };
    await expect(
      timedContracts.create(user.userId, randomUUID(), {
        ...body,
        investmentAmount: "9.99",
      }),
    ).rejects.toMatchObject({ code: "INVALID_INVESTMENT_AMOUNT" });
    const first = await timedContracts.create(user.userId, randomUUID(), body);
    const second = await timedContracts.create(user.userId, randomUUID(), body);
    await expect(
      timedContracts.create(user.userId, randomUUID(), body),
    ).rejects.toMatchObject({ code: "INSUFFICIENT_FUNDS" });
    const page = await timedContracts.list(user.userId, {
      accountMode: AccountMode.DEMO,
      result: "PENDING",
      limit: 1,
    });
    expect(page.items[0]?.id).toBe(second.id);
    const next = await timedContracts.list(user.userId, {
      accountMode: AccountMode.DEMO,
      result: "PENDING",
      limit: 1,
      cursor: page.nextCursor!,
    });
    expect(next.items[0]?.id).toBe(first.id);
  });

  function orderBody(quantity: string): CreateOrderDto {
    return {
      accountMode: AccountMode.DEMO,
      instrumentId: "btc-usd",
      clientOrderId: `test-client:${randomUUID()}`,
      side: OrderSide.BUY,
      orderType: "MARKET",
      quantity,
    };
  }

  async function available(accountId: string): Promise<Prisma.Decimal> {
    const wallet = await prisma.wallet.findUniqueOrThrow({
      where: { accountId_currencyCode: { accountId, currencyCode: "BDT" } },
      select: { availableProjection: true },
    });
    return wallet.availableProjection;
  }

  async function provisionUser(balance: string): Promise<TestUser> {
    const suffix = randomUUID();
    return prisma.$transaction(async (tx) => {
      await tx.currency.upsert({
        where: { code: "BDT" },
        create: { code: "BDT", name: "Bangladeshi Taka", precision: 2 },
        update: {},
      });
      const user = await tx.user.create({
        data: {
          email: `trading-integration-${suffix}@example.invalid`,
          phone: `+880${suffix.replaceAll("-", "").slice(0, 11)}`,
          passwordHash: "integration-test-only",
        },
      });
      const demo = await tx.account.create({
        data: { userId: user.id, mode: AccountMode.DEMO },
      });
      const real = await tx.account.create({
        data: { userId: user.id, mode: AccountMode.REAL },
      });
      const amount = new Prisma.Decimal(balance);
      await tx.wallet.createMany({
        data: [
          {
            accountId: demo.id,
            currencyCode: "BDT",
            availableProjection: amount,
          },
          {
            accountId: real.id,
            currencyCode: "BDT",
          },
        ],
      });
      const accounts = await ledger.ensureAccountLedgerAccounts(
        tx,
        demo.id,
        AccountMode.DEMO,
      );
      await ledger.post(tx, {
        type: LedgerTransactionType.DEMO_FUNDING,
        idempotencyKey: `trading-integration-funding:${suffix}`,
        description: "Trading integration test funds",
        entries: [
          {
            ledgerAccountId: accounts.control,
            direction: LedgerDirection.DEBIT,
            amount,
          },
          {
            ledgerAccountId: accounts.available,
            direction: LedgerDirection.CREDIT,
            amount,
          },
        ],
      });
      return {
        userId: user.id,
        demoAccountId: demo.id,
        realAccountId: real.id,
      };
    });
  }
});
