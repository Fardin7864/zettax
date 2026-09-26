import { Prisma } from "@prisma/client";
import { describe, expect, it } from "vitest";
import {
  allocatePredictionPool,
  predictionOutcome,
} from "../src/prediction/pool";

const amount = (value: string) => new Prisma.Decimal(value);

describe("prediction pool", () => {
  it("splits every cent of the losing pool among winners", () => {
    const payouts = allocatePredictionPool(
      [
        { id: "a", side: "YES", stake: amount("1.00") },
        { id: "b", side: "YES", stake: amount("1.00") },
        { id: "c", side: "YES", stake: amount("1.00") },
        { id: "d", side: "NO", stake: amount("1.00") },
      ],
      "YES",
    );
    expect(
      [...payouts.values()]
        .reduce((sum, value) => sum.plus(value), amount("0"))
        .toFixed(2),
    ).toBe("4.00");
    expect(payouts.get("a")?.toFixed(2)).toBe("1.34");
    expect(payouts.get("b")?.toFixed(2)).toBe("1.33");
    expect(payouts.get("d")?.toFixed(2)).toBe("0.00");
  });

  it("refunds everyone if no one selected the winning side", () => {
    const payouts = allocatePredictionPool(
      [{ id: "a", side: "NO", stake: amount("5.25") }],
      "YES",
    );
    expect(payouts.get("a")?.toFixed(2)).toBe("5.25");
  });

  it("uses a strict price threshold", () => {
    expect(predictionOutcome(amount("100"), amount("100"), "ABOVE")).toBe("NO");
    expect(predictionOutcome(amount("99"), amount("100"), "BELOW")).toBe("YES");
  });
});
