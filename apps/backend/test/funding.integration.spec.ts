import { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { PrismaService } from "../src/database/prisma.service";
import { LedgerService } from "../src/database/ledger.service";
import { OutboxService } from "../src/database/outbox.service";
import { ComplianceService } from "../src/compliance/compliance.service";
import { ControlService } from "../src/operations/control.service";
import { FundingService } from "../src/funding/funding.service";
const suite =
  process.env.RUN_DATABASE_INTEGRATION === "true" ? describe : describe.skip;
suite("funding evidence and double-entry settlement", () => {
  const prisma = new PrismaService();
  const config = new ConfigService({
    COMPLIANCE_MODE: "PRODUCTION_APPROVED",
    ENABLE_DEPOSITS: "true",
    ENABLE_WITHDRAWALS: "true",
  });
  // Isolated fixtures test funding transitions independently of real release approval.
  const admitted = {
    requireReady: () => Promise.resolve(),
    readiness: () => Promise.resolve({ ready: true }),
  } as ControlService;
  const funding = new FundingService(
    prisma,
    new ComplianceService(config),
    new LedgerService(),
    admitted,
    new OutboxService(),
  );
  const audit = { requestId: `funding-test-${randomUUID()}` };
  let user: string,
    account: string,
    maker: string,
    checker: string,
    method: string,
    depositId: string,
    withdrawalId: string;
  async function evidence(
    ownerId: string,
    ownerType: "USER" | "ADMIN",
    purpose: string,
  ) {
    return prisma.evidenceFile.create({
      data: {
        ownerId,
        ownerType,
        purpose,
        objectKey: `test/${randomUUID()}`,
        filename: "fixture.png",
        mimeType: "image/png",
        sha256: "fixture-only",
        sizeBytes: 1,
      },
    });
  }
  async function wallet() {
    return prisma.wallet.findUniqueOrThrow({
      where: {
        accountId_currencyCode: { accountId: account, currencyCode: "BDT" },
      },
    });
  }
  beforeAll(async () => {
    await prisma.$connect();
    user = (
      await prisma.user.create({
        data: {
          email: `funding-${randomUUID()}@example.invalid`,
          passwordHash: "fixture",
          depositEnabled: true,
          withdrawalEnabled: true,
        },
      })
    ).id;
    account = (
      await prisma.account.create({
        data: {
          userId: user,
          mode: "REAL",
          wallets: { create: { currencyCode: "BDT" } },
        },
      })
    ).id;
    maker = (
      await prisma.adminUser.create({
        data: {
          email: `funding-maker-${randomUUID()}@example.invalid`,
          passwordHash: "fixture",
        },
      })
    ).id;
    checker = (
      await prisma.adminUser.create({
        data: {
          email: `funding-checker-${randomUUID()}@example.invalid`,
          passwordHash: "fixture",
        },
      })
    ).id;
    method = (
      await prisma.paymentMethod.findFirstOrThrow({
        where: { type: "BKASH", isEnabled: true },
      })
    ).id;
    await prisma.kycCase.create({ data: { userId: user, status: "APPROVED" } });
  });
  afterAll(async () => {
    await prisma.adminUser.updateMany({
      where: { id: { in: [maker, checker].filter(Boolean) } },
      data: { active: false },
    });
    await prisma.$disconnect();
  });
  it("rejects missing/foreign evidence and deduplicates concurrent claims", async () => {
    const key = `test:${randomUUID()}`,
      receipt = await evidence(user, "USER", "DEPOSIT");
    const body = {
      paymentMethodId: method,
      amount: "1000.00",
      senderMobile: "+8801712345678",
      providerTransactionId: randomUUID().replaceAll("-", "").slice(0, 16),
      evidenceObjectKey: receipt.objectKey,
    };
    await expect(
      funding.createDeposit(
        user,
        key,
        { ...body, evidenceObjectKey: "missing" },
        audit,
      ),
    ).rejects.toMatchObject({ code: "EVIDENCE_REQUIRED" });
    const foreign = await evidence(randomUUID(), "USER", "DEPOSIT");
    await expect(
      funding.createDeposit(
        user,
        key,
        { ...body, evidenceObjectKey: foreign.objectKey },
        audit,
      ),
    ).rejects.toMatchObject({ code: "EVIDENCE_REQUIRED" });
    const [one, two] = await Promise.all([
      funding.createDeposit(user, key, body, audit),
      funding.createDeposit(user, key, body, audit),
    ]);
    expect(one.id).toBe(two.id);
    depositId = one.id;
    await expect(
      funding.createDeposit(user, key, { ...body, amount: "1001.00" }, audit),
    ).rejects.toMatchObject({ code: "IDEMPOTENCY_KEY_REUSED" });
    expect((await wallet()).availableProjection.toFixed(2)).toBe("0.00");
  });
  it("requires independent verification, posts credit exactly once and publishes durable events", async () => {
    await expect(
      funding.approveDeposit(depositId, maker, audit),
    ).rejects.toMatchObject({ code: "INDEPENDENT_REVIEW_REQUIRED" });
    await funding.verifyDeposit(
      depositId,
      maker,
      "Fixture provider statement line 1",
      audit,
    );
    await expect(
      funding.approveDeposit(depositId, maker, audit),
    ).rejects.toMatchObject({ code: "INDEPENDENT_REVIEW_REQUIRED" });
    await Promise.all([
      funding.approveDeposit(depositId, checker, audit),
      funding.approveDeposit(depositId, checker, audit),
    ]);
    expect((await wallet()).availableProjection.toFixed(2)).toBe("1000.00");
    expect(
      await prisma.ledgerTransaction.count({
        where: { idempotencyKey: `deposit:${depositId}:credit` },
      }),
    ).toBe(1);
    expect(
      await prisma.accountEvent.count({
        where: { userId: user, eventType: "FUNDING_UPDATED" },
      }),
    ).toBeGreaterThanOrEqual(2);
  });
  it("locks once, requires a checker and clean payout evidence, and cannot double-pay", async () => {
    const body = {
        paymentMethodId: method,
        amount: "300.00",
        receiverMobile: "+8801712345678",
      },
      key = `test:${randomUUID()}`;
    const [one, two] = await Promise.all([
      funding.createWithdrawal(user, key, body, audit),
      funding.createWithdrawal(user, key, body, audit),
    ]);
    expect(one.id).toBe(two.id);
    withdrawalId = one.id;
    expect((await wallet()).lockedProjection.toFixed(2)).toBe("300.00");
    expect((await wallet()).availableProjection.toFixed(2)).toBe("700.00");
    await funding.transitionWithdrawal(
      withdrawalId,
      maker,
      "START_REVIEW",
      audit,
    );
    await expect(
      funding.transitionWithdrawal(withdrawalId, maker, "APPROVE", audit),
    ).rejects.toMatchObject({ code: "INDEPENDENT_REVIEW_REQUIRED" });
    await funding.transitionWithdrawal(withdrawalId, checker, "APPROVE", audit);
    await funding.transitionWithdrawal(
      withdrawalId,
      maker,
      "START_PROCESSING",
      audit,
    );
    const receipt = await evidence(maker, "ADMIN", "WITHDRAWAL"),
      paid = {
        providerTransactionId: randomUUID().replaceAll("-", "").slice(0, 16),
        evidenceObjectKey: receipt.objectKey,
      };
    await expect(
      funding.markWithdrawalPaid(withdrawalId, checker, paid, audit),
    ).rejects.toThrow();
    await expect(
      funding.markWithdrawalPaid(
        withdrawalId,
        maker,
        { ...paid, evidenceObjectKey: "missing" },
        audit,
      ),
    ).rejects.toMatchObject({ code: "EVIDENCE_REQUIRED" });
    await Promise.all([
      funding.markWithdrawalPaid(withdrawalId, maker, paid, audit),
      funding.markWithdrawalPaid(withdrawalId, maker, paid, audit),
    ]);
    expect((await wallet()).lockedProjection.toFixed(2)).toBe("0.00");
    expect((await wallet()).availableProjection.toFixed(2)).toBe("700.00");
    await expect(
      prisma.evidenceFile.update({
        where: { id: receipt.id },
        data: { claimedBy: "another-request" },
      }),
    ).rejects.toThrow();
  });
  it("returns cancelled funds once and prevents overspending", async () => {
    const body = {
      paymentMethodId: method,
      amount: "200.00",
      receiverMobile: "+8801712345678",
    };
    const row = await funding.createWithdrawal(
      user,
      `test:${randomUUID()}`,
      body,
      audit,
    );
    await funding.cancelWithdrawal(row.id, user, audit);
    await funding.cancelWithdrawal(row.id, user, audit);
    expect((await wallet()).availableProjection.toFixed(2)).toBe("700.00");
    await expect(
      funding.createWithdrawal(
        user,
        `test:${randomUUID()}`,
        { ...body, amount: "800.00" },
        audit,
      ),
    ).rejects.toMatchObject({ code: "INSUFFICIENT_FUNDS" });
    const closed = new FundingService(
      prisma,
      new ComplianceService(config),
      new LedgerService(),
      new ControlService(
        prisma,
        new ConfigService({ RELEASE_VERSION: "never-approved" }),
      ),
      new OutboxService(),
    );
    await expect(
      closed.createWithdrawal(user, `test:${randomUUID()}`, body, audit),
    ).rejects.toMatchObject({ code: "RELEASE_NOT_APPROVED" });
  });
});
