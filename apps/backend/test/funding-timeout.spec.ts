import { Prisma } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import { FundingService } from "../src/funding/funding.service";

type TransactionRunner = {
  withSerializableRetry: (
    work: (tx: Prisma.TransactionClient) => Promise<unknown>,
  ) => Promise<unknown>;
};
function runner(transaction: ReturnType<typeof vi.fn>) {
  return new FundingService(
    { $transaction: transaction } as never,
    {} as never,
    {} as never,
    {} as never,
    {} as never,
  ) as unknown as TransactionRunner;
}

describe("hosted funding transaction timeout", () => {
  it("allows hosted database latency while preserving serializable isolation", async () => {
    const transaction = vi.fn().mockResolvedValue("committed");
    expect(
      await runner(transaction).withSerializableRetry(async () => "committed"),
    ).toBe("committed");
    expect(transaction.mock.calls[0]![1]).toEqual({
      isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
      timeout: 30_000,
      maxWait: 10_000,
    });
  });
  it("returns an actionable recovery error rather than an internal server error", async () => {
    const transaction = vi
      .fn()
      .mockRejectedValue(
        new Prisma.PrismaClientKnownRequestError("expired", {
          code: "P2028",
          clientVersion: "test",
        }),
      );
    await expect(
      runner(transaction).withSerializableRetry(async () => undefined),
    ).rejects.toMatchObject({ code: "FUNDING_TRANSACTION_TIMEOUT" });
    expect(transaction).toHaveBeenCalledTimes(1);
  });
});
