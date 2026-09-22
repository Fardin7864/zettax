import { describe, expect, it } from "vitest";
import { parseSequence } from "../src/accounts/account-realtime.gateway";
import { accountEventResponse } from "../src/accounts/account-events.service";

describe("private account realtime protocol", () => {
  it("accepts only non-negative decimal sequence cursors", () => {
    expect(parseSequence("0")).toBe(0n);
    expect(parseSequence("42")).toBe(42n);
    expect(parseSequence(undefined)).toBeNull();
    expect(parseSequence("-1")).toBeNull();
    expect(parseSequence("1.5")).toBeNull();
    expect(parseSequence(42)).toBeNull();
  });

  it("serializes bigint sequences and timestamps for clients", () => {
    expect(
      accountEventResponse({
        id: "event-id",
        sequence: 7n,
        eventType: "order.filled",
        payload: { amount: "10.00" },
        occurredAt: new Date("2026-09-09T06:00:00.000Z"),
      }),
    ).toEqual({
      schemaVersion: 1,
      id: "event-id",
      sequence: "7",
      type: "order.filled",
      payload: { amount: "10.00" },
      occurredAt: "2026-09-09T06:00:00.000Z",
    });
  });
});
