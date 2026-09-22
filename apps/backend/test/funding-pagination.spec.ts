import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { DepositStatus, WithdrawalStatus } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import { FundingService } from "../src/funding/funding.service";
import { AdminDepositQueryDto, AdminWithdrawalQueryDto } from "../src/funding/funding-pagination.dto";

describe("paginated admin funding history", () => {
  for (const kind of ["deposit", "withdrawal"] as const) {
    it(`includes every ${kind} status by default and uses a bounded stable page`, async () => {
      const findMany = vi.fn().mockResolvedValue([{ id: "request" }]);
      const count = vi.fn().mockResolvedValue(61);
      const tx = { [`${kind}Request`]: { findMany, count } };
      const prisma = { $transaction: vi.fn(async (work) => work(tx)) };
      const service = new FundingService(prisma as never, { isVirtual: true } as never, {} as never, {} as never, {} as never);
      const result = kind === "deposit" ? await service.listDepositsForReview(undefined, 2, 25) : await service.listWithdrawalsForReview(undefined, 2, 25);
      expect(findMany).toHaveBeenCalledWith(expect.objectContaining({ where: {}, skip: 25, take: 25, orderBy: [{ createdAt: "desc" }, { id: "desc" }] }));
      expect(count).toHaveBeenCalledWith({ where: {} });
      expect(result).toMatchObject({ total: 61, page: 2, pageSize: 25, totalPages: 3, items: [{ id: "request", virtualFunding: true }] });
    });
    it(`filters ${kind} history and counts with the same status`, async () => {
      const findMany = vi.fn().mockResolvedValue([]), count = vi.fn().mockResolvedValue(0);
      const prisma = { $transaction: vi.fn(async (work) => work({ [`${kind}Request`]: { findMany, count } })) };
      const service = new FundingService(prisma as never, {} as never, {} as never, {} as never, {} as never);
      const status = kind === "deposit" ? DepositStatus.CREDITED : WithdrawalStatus.PAID;
      const result = kind === "deposit" ? await service.listDepositsForReview(DepositStatus.CREDITED) : await service.listWithdrawalsForReview(WithdrawalStatus.PAID);
      expect(findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { status } }));
      expect(count).toHaveBeenCalledWith({ where: { status } });
      expect(result.totalPages).toBe(1);
    });
  }
  it("validates page bounds, page size and status before querying", async () => {
    expect(await validate(plainToInstance(AdminDepositQueryDto, { page: "2", pageSize: "50", status: "CREDITED" }))).toHaveLength(0);
    for (const query of [{ page: "0" }, { page: "1.5" }, { pageSize: "101" }, { status: "INVALID" }]) {
      expect((await validate(plainToInstance(AdminWithdrawalQueryDto, query))).length).toBeGreaterThan(0);
    }
  });
});
