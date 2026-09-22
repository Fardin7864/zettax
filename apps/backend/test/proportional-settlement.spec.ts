import { ContractDirection, Prisma } from "@prisma/client";
import { describe, expect, it } from "vitest";
import { proportionalSettlement } from "../src/timed-contracts/proportional-settlement";
const d = (n: string) => new Prisma.Decimal(n);
describe("proportional expiry settlement", () => {
  it.each([
    ["UP", "102", "1020.00"],
    ["UP", "98", "980.00"],
    ["DOWN", "102", "980.00"],
    ["DOWN", "98", "1020.00"],
    ["UP", "100", "1000.00"],
    ["DOWN", "100", "1000.00"],
    ["DOWN", "250", "0.00"],
    ["UP", "0", "0.00"],
    ["UP", "1000", "10000.00"],
  ])("%s at %s returns %s without a profit cap", (side, price, expected) => {
    expect(
      proportionalSettlement(
        d("1000"),
        d("100"),
        d(price),
        side as ContractDirection,
        d("0"),
      ).payout.toFixed(2),
    ).toBe(expected);
  });
  it("charges only positive profit and accounts for each paisa", () => {
    const win = proportionalSettlement(
      d("1000"),
      d("100"),
      d("102"),
      "UP",
      d("0.1"),
    );
    expect(win.grossPnl.toFixed(2)).toBe("20.00");
    expect(win.fee.toFixed(2)).toBe("2.00");
    expect(win.payout.toFixed(2)).toBe("1018.00");
    expect(
      proportionalSettlement(
        d("1000"),
        d("100"),
        d("98"),
        "UP",
        d("0.1"),
      ).fee.isZero(),
    ).toBe(true);
  });
  it("rejects invalid fees and stakes", () => {
    expect(() =>
      proportionalSettlement(d("0"), d("100"), d("102"), "UP", d("0")),
    ).toThrow();
    expect(() =>
      proportionalSettlement(d("10"), d("0"), d("102"), "UP", d("0")),
    ).toThrow();
    expect(() =>
      proportionalSettlement(d("10"), d("100"), d("102"), "UP", d("1.1")),
    ).toThrow();
  });
  it("settles a small positive virtual stake", () => {
    expect(
      proportionalSettlement(
        d("0.01"),
        d("100"),
        d("102"),
        "UP",
        d("0"),
      ).payout.toFixed(2),
    ).toBe("0.01");
  });
});
