import { Prisma } from "@prisma/client";
import { describe, expect, it, vi } from "vitest";
import {
  bdtFromWithdrawal,
  parseConversionRate,
  readConversionRates,
  usdFromDeposit,
} from "../src/funding/conversion-rates";

describe("customer wallet conversion", () => {
  it("uses distinct fallback rates when the admin has not saved settings", async () => {
    const db = { systemConfig: { findMany: vi.fn().mockResolvedValue([]) } };
    const rates = await readConversionRates(db as never);
    expect(rates.depositBdtPerUsd.toString()).toBe("125");
    expect(rates.withdrawalBdtPerUsd.toString()).toBe("118");
    expect(usdFromDeposit(new Prisma.Decimal("1250"), rates.depositBdtPerUsd).toFixed(2)).toBe("10.00");
    expect(bdtFromWithdrawal(new Prisma.Decimal("10"), rates.withdrawalBdtPerUsd).toFixed(2)).toBe("1180.00");
  });

  it("rounds once at the boundary and rejects an unrepresentable deposit", () => {
    expect(usdFromDeposit(new Prisma.Decimal("126"), new Prisma.Decimal("125")).toFixed(2)).toBe("1.01");
    expect(bdtFromWithdrawal(new Prisma.Decimal("1.01"), new Prisma.Decimal("118")).toFixed(2)).toBe("119.18");
    expect(() => usdFromDeposit(new Prisma.Decimal("0.01"), new Prisma.Decimal("125"))).toThrow();
  });

  it("accepts only bounded positive admin rates", () => {
    expect(parseConversionRate("125.1234").toFixed(4)).toBe("125.1234");
    for (const value of ["0", "10000", "118.12345", "NaN", "-1"]) {
      expect(() => parseConversionRate(value)).toThrow();
    }
  });
});
