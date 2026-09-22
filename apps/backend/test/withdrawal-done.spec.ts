import { Prisma, WithdrawalStatus } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import { FundingService } from "../src/funding/funding.service";

function setup(status: WithdrawalStatus, virtual = true) {
  let request = {
    id: "withdrawal-1",
    userId: "user-1",
    accountId: "account-1",
    amount: new Prisma.Decimal(100),
    status,
    reviewStartedBy: "admin-1",
    approvedBy: null as string | null,
    providerTransactionId: null as string | null,
  };
  const tx = {
    $queryRaw: vi.fn().mockResolvedValue([]),
    withdrawalRequest: {
      findUnique: vi.fn(async () => request),
      update: vi.fn(async ({ data }) => {
        const next = { ...request, ...data };
        // Mirror withdrawal_independent_review from PostgreSQL.
        if (next.approvedBy && next.reviewStartedBy === next.approvedBy)
          throw new Error("withdrawal_independent_review");
        request = next;
        return request;
      }),
    },
    wallet: { updateMany: vi.fn().mockResolvedValue({ count: 1 }) },
    evidenceFile: { findUnique: vi.fn().mockResolvedValue(null) },
    auditLog: { create: vi.fn().mockResolvedValue({}) },
  };
  const ledger = {
    lockWallet: vi.fn().mockResolvedValue(undefined),
    ensureAccountLedgerAccounts: vi.fn().mockResolvedValue({
      control: "cash",
      available: "available",
      locked: "locked",
    }),
    post: vi.fn().mockResolvedValue({ id: "settlement-1" }),
  };
  const outbox = { enqueueAccount: vi.fn().mockResolvedValue(undefined) };
  const service = new FundingService(
    { $transaction: vi.fn(async (work) => work(tx)) } as never,
    { isVirtual: virtual, isEnabled: () => true } as never,
    ledger as never,
    {} as never,
    outbox as never,
  );
  return { service, tx, ledger, outbox };
}
const input = { providerTransactionId: "VIRTUAL123456" },
  audit = { requestId: "test" };
describe("virtual withdrawal Done", () => {
  it.each([
    WithdrawalStatus.REQUESTED,
    WithdrawalStatus.UNDER_REVIEW,
    WithdrawalStatus.APPROVED,
    WithdrawalStatus.PROCESSING,
  ])("completes %s atomically and notifies once", async (status) => {
    const { service, tx, ledger, outbox } = setup(status);
    const result = await service.markWithdrawalPaid(
      "withdrawal-1",
      "admin-1",
      input,
      audit,
      true,
    );
    expect(result.status).toBe(WithdrawalStatus.PAID);
    expect(tx.wallet.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { lockedProjection: { decrement: new Prisma.Decimal(100) } },
      }),
    );
    expect(ledger.post).toHaveBeenCalledWith(
      tx,
      expect.objectContaining({
        idempotencyKey: "withdrawal:withdrawal-1:settle",
      }),
    );
    expect(outbox.enqueueAccount).toHaveBeenCalledWith(
      tx,
      "user-1",
      expect.objectContaining({
        payload: expect.objectContaining({ status: "PAID", amount: "100.00" }),
      }),
    );
    await service.markWithdrawalPaid(
      "withdrawal-1",
      "admin-1",
      input,
      audit,
      true,
    );
    expect(ledger.post).toHaveBeenCalledTimes(1);
    expect(outbox.enqueueAccount).toHaveBeenCalledTimes(1);
  });
  it.each([WithdrawalStatus.REJECTED, WithdrawalStatus.CANCELLED])(
    "cannot complete %s",
    async (status) => {
      const { service, ledger } = setup(status);
      await expect(
        service.markWithdrawalPaid(
          "withdrawal-1",
          "admin-1",
          input,
          audit,
          true,
        ),
      ).rejects.toMatchObject({ code: "WITHDRAWAL_INVALID_STATE" });
      expect(ledger.post).not.toHaveBeenCalled();
    },
  );
  it("does not bypass the real-money withdrawal workflow", async () => {
    const { service, ledger } = setup(WithdrawalStatus.REQUESTED, false);
    await expect(
      service.markWithdrawalPaid("withdrawal-1", "admin-1", input, audit, true),
    ).rejects.toMatchObject({ code: "VIRTUAL_FUNDING_REQUIRED" });
    await expect(
      service.markWithdrawalPaid("withdrawal-1", "admin-1", input, audit),
    ).rejects.toMatchObject({ code: "WITHDRAWAL_INVALID_STATE" });
    expect(ledger.post).not.toHaveBeenCalled();
  });
});
