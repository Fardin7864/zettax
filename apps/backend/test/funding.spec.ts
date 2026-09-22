import { Prisma, WithdrawalStatus } from "@prisma/client";
import { describe, expect, it } from "vitest";
import { FundingController } from "../src/funding/funding.controller";
import { FundingError } from "../src/funding/funding.errors";
import type { FundingService } from "../src/funding/funding.service";
import type { EvidenceService } from "../src/funding/evidence.service";
import type { PrismaService } from "../src/database/prisma.service";
import {
  canReleaseWithdrawal,
  resolveWithdrawalTransition,
} from "../src/funding/funding.state";
import {
  assertBalanced,
  normalizeProviderTransactionId,
  parseBdt,
  validateBangladeshMobile,
  validateIdempotencyKey,
} from "../src/funding/funding.validation";

describe("funding input safety", () => {
  it("propagates asynchronous funding errors through Nest's exception pipeline", async () => {
    const service = {
      listPaymentMethods: () =>
        Promise.reject(
          new FundingError(
            "DEPOSIT_DISABLED",
            "Deposits require server-side production approval",
            403,
          ),
        ),
    } as unknown as FundingService;
    const controller = new FundingController(
      service,
      {} as EvidenceService,
      {} as PrismaService,
    );

    await expect(controller.listDepositMethods()).rejects.toMatchObject({
      code: "DEPOSIT_DISABLED",
    });
  });

  it("normalizes equivalent provider transaction IDs for duplicate detection", () => {
    expect(normalizeProviderTransactionId(" ab-12 cd-34 ")).toBe("AB12CD34");
  });

  it("rejects malformed transaction IDs and mobile numbers", () => {
    expect(() => normalizeProviderTransactionId("../../bad")).toThrow(
      FundingError,
    );
    expect(() => validateBangladeshMobile("01712345678")).toThrow(FundingError);
  });

  it("accepts canonical Bangladesh numbers", () => {
    expect(validateBangladeshMobile("+880 1712-345678")).toBe("+8801712345678");
  });

  it("requires reusable-safe idempotency keys", () => {
    expect(validateIdempotencyKey("deposit:client-123")).toBe(
      "deposit:client-123",
    );
    expect(() => validateIdempotencyKey("short")).toThrow(FundingError);
  });

  it("uses exact decimal money and rejects excess precision", () => {
    expect(parseBdt("1000.10").toFixed(2)).toBe("1000.10");
    expect(() => parseBdt("1.001")).toThrow(FundingError);
    expect(() => parseBdt("0")).toThrow(FundingError);
  });
});

describe("double-entry ledger invariants", () => {
  it("accepts only equal positive debit and credit totals", () => {
    expect(() =>
      assertBalanced([
        { direction: "DEBIT", amount: new Prisma.Decimal("25.50") },
        { direction: "CREDIT", amount: new Prisma.Decimal("20.00") },
        { direction: "CREDIT", amount: new Prisma.Decimal("5.50") },
      ]),
    ).not.toThrow();
  });

  it("fails closed on an unbalanced journal", () => {
    expect(() =>
      assertBalanced([
        { direction: "DEBIT", amount: new Prisma.Decimal("25.50") },
        { direction: "CREDIT", amount: new Prisma.Decimal("25.49") },
      ]),
    ).toThrow(FundingError);
  });
});

describe("withdrawal locking state machine", () => {
  it("advances through review, approval and processing in order", () => {
    expect(
      resolveWithdrawalTransition(WithdrawalStatus.REQUESTED, "START_REVIEW"),
    ).toEqual({
      next: WithdrawalStatus.UNDER_REVIEW,
      replay: false,
    });
    expect(
      resolveWithdrawalTransition(WithdrawalStatus.UNDER_REVIEW, "APPROVE")
        .next,
    ).toBe(WithdrawalStatus.APPROVED);
    expect(
      resolveWithdrawalTransition(WithdrawalStatus.APPROVED, "START_PROCESSING")
        .next,
    ).toBe(WithdrawalStatus.PROCESSING);
  });

  it("makes repeated transition calls idempotent", () => {
    expect(
      resolveWithdrawalTransition(WithdrawalStatus.APPROVED, "APPROVE"),
    ).toEqual({
      next: WithdrawalStatus.APPROVED,
      replay: true,
    });
  });

  it("rejects skipped transitions and release after processing", () => {
    expect(() =>
      resolveWithdrawalTransition(
        WithdrawalStatus.REQUESTED,
        "START_PROCESSING",
      ),
    ).toThrow(FundingError);
    expect(canReleaseWithdrawal(WithdrawalStatus.PROCESSING, false)).toBe(
      false,
    );
    expect(canReleaseWithdrawal(WithdrawalStatus.UNDER_REVIEW, true)).toBe(
      false,
    );
    expect(canReleaseWithdrawal(WithdrawalStatus.APPROVED, false)).toBe(true);
  });
});
