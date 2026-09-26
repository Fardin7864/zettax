import { describe, expect, it, vi } from "vitest";
import { PredictionService } from "../src/prediction/prediction.service";

describe("prediction real-money access", () => {
  it("rejects real-money stakes before any wallet mutation when approval is absent", async () => {
    const prisma = { $transaction: vi.fn() };
    const controls = { requireReady: vi.fn() };
    const compliance = {
      mode: "DEMO_ONLY",
      isEnabled: vi.fn(() => false),
    };
    const service = new PredictionService(
      prisma as never,
      compliance as never,
      {} as never,
      {} as never,
      {} as never,
      controls as never,
      {} as never,
    );
    await expect(
      service.place("user-1", "question-1", "attempt-1", {
        accountMode: "REAL",
        side: "YES",
        stake: "10.00",
      }),
    ).rejects.toMatchObject({ code: "REAL_PREDICTIONS_DISABLED" });
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(controls.requireReady).not.toHaveBeenCalled();
  });
});
