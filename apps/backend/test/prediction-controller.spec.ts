import { describe, expect, it, vi } from "vitest";
import { PredictionController } from "../src/prediction/prediction.controller";

describe("prediction controller responses", () => {
  it("resolves service results before wrapping them in data", async () => {
    const list = { items: [], nextCursor: null };
    const question = { id: "question-1" };
    const positions = [{ id: "position-1" }];
    const service = {
      list: vi.fn(async () => list),
      get: vi.fn(async () => question),
      myPositions: vi.fn(async () => positions),
      create: vi.fn(async () => question),
      place: vi.fn(async () => positions[0]),
    };
    const controller = new PredictionController(service as never);
    const customer = { auth: { userId: "user-1" } } as never;
    const admin = {
      user: {
        permissions: ["trading.configure"],
        stepUpUntil: Date.now() + 60_000,
      },
    } as never;

    expect(await controller.questions({})).toEqual({ data: list });
    expect(await controller.question("question-1")).toEqual({ data: question });
    expect(await controller.mine(customer)).toEqual({ data: positions });
    expect(await controller.create(customer, {} as never)).toEqual({
      data: question,
    });
    expect(await controller.platformCreate(admin, {} as never)).toEqual({
      data: question,
    });
    expect(
      await controller.place(customer, "question-1", "attempt-01", {} as never),
    ).toEqual({ data: positions[0] });
  });
});
