import { LedgerDirection, LedgerTransactionType, Prisma } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import { IdempotencyService } from "../src/database/idempotency.service";
import { LedgerService } from "../src/database/ledger.service";

describe("durable command foundation", () => {
  it("uses a deterministic canonical request hash", () => {
    const service = new IdempotencyService();
    expect(service.hash({ amount: "10.00", nested: { b: 2, a: 1 } })).toBe(
      service.hash({ nested: { a: 1, b: 2 }, amount: "10.00" }),
    );
    expect(service.hash({ amount: "10.01" })).not.toBe(
      service.hash({ amount: "10.00" }),
    );
  });

  it("rejects an unbalanced journal before touching PostgreSQL", async () => {
    const tx = {
      ledgerAccount: { findMany: vi.fn() },
      ledgerTransaction: { create: vi.fn() },
    };
    await expect(
      new LedgerService().post(tx as never, {
        type: LedgerTransactionType.ADJUSTMENT,
        idempotencyKey: "test:unbalanced",
        description: "test",
        entries: [
          {
            ledgerAccountId: "a",
            direction: LedgerDirection.DEBIT,
            amount: new Prisma.Decimal("10"),
          },
          {
            ledgerAccountId: "b",
            direction: LedgerDirection.CREDIT,
            amount: new Prisma.Decimal("9"),
          },
        ],
      }),
    ).rejects.toMatchObject({ code: "LEDGER_UNBALANCED" });
    expect(tx.ledgerAccount.findMany).not.toHaveBeenCalled();
  });

  it("rejects cross-currency and cross-customer journals", async () => {
    const tx = {
      ledgerAccount: {
        findMany: vi.fn().mockResolvedValue([
          { id: "a", accountId: "one", currencyCode: "BDT", mode: "DEMO" },
          { id: "b", accountId: "two", currencyCode: "USD", mode: "REAL" },
        ]),
      },
      ledgerTransaction: { create: vi.fn() },
    };
    await expect(
      new LedgerService().post(tx as never, {
        type: LedgerTransactionType.ADJUSTMENT,
        idempotencyKey: "test:scope",
        description: "test",
        entries: [
          {
            ledgerAccountId: "a",
            direction: LedgerDirection.DEBIT,
            amount: new Prisma.Decimal("10"),
          },
          {
            ledgerAccountId: "b",
            direction: LedgerDirection.CREDIT,
            amount: new Prisma.Decimal("10"),
          },
        ],
      }),
    ).rejects.toMatchObject({ code: "LEDGER_UNBALANCED" });
    expect(tx.ledgerTransaction.create).not.toHaveBeenCalled();
  });
});
