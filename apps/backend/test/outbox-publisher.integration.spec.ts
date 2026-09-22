import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { OutboxDispatcher } from "../src/database/outbox-dispatcher";
import { OutboxPublisherService } from "../src/database/outbox-publisher.service";
import { PrismaService } from "../src/database/prisma.service";

const enabled = process.env.RUN_DATABASE_INTEGRATION === "true";
const suite = enabled ? describe : describe.skip;

suite("PostgreSQL outbox claiming and retry", () => {
  const prisma = new PrismaService();

  beforeAll(async () => {
    await prisma.$connect();
    await prisma.outboxEvent.updateMany({
      where: { aggregateType: "IntegrationTest", publishedAt: null },
      data: { publishedAt: new Date(), claimToken: null, claimedAt: null },
    });
  });
  afterAll(() => prisma.$disconnect());

  it("claims and marks a successfully dispatched event", async () => {
    const event = await createEvent(new Date("2000-01-01T00:00:00.000Z"));
    const delivered: string[] = [];
    const publisher = new OutboxPublisherService(prisma, {
      dispatch(value) {
        delivered.push(value.id);
        return Promise.resolve();
      },
    });

    expect(await publisher.publishBatch(1)).toEqual({
      claimed: 1,
      published: 1,
      failed: 0,
    });
    expect(delivered).toEqual([event.id]);
    expect(
      await prisma.outboxEvent.findUniqueOrThrow({ where: { id: event.id } }),
    ).toMatchObject({
      attempts: 1,
      claimToken: null,
      claimedAt: null,
      lastError: null,
    });
  });

  it("releases a failed claim, redacts its error, and retries later", async () => {
    const event = await createEvent(new Date("2000-01-02T00:00:00.000Z"));
    const failing = new OutboxPublisherService(prisma, {
      dispatch() {
        return Promise.reject(new Error("secret upstream credential abc123"));
      },
    });

    expect(await failing.publishBatch(1)).toEqual({
      claimed: 1,
      published: 0,
      failed: 1,
    });
    const pending = await prisma.outboxEvent.findUniqueOrThrow({
      where: { id: event.id },
    });
    expect(pending.publishedAt).toBeNull();
    expect(pending.claimToken).toBeNull();
    expect(pending.claimedAt).toBeNull();
    expect(pending.attempts).toBe(1);
    expect(pending.lastError).toBe("Delivery failed (Error)");
    expect(pending.lastError).not.toContain("abc123");
    await failing.publishBatch(1);
    expect(
      await prisma.outboxEvent.findUniqueOrThrow({ where: { id: event.id } }),
    ).toMatchObject({ attempts: 1, publishedAt: null });

    await prisma.outboxEvent.update({
      where: { id: event.id },
      data: { nextAttemptAt: new Date("2000-01-02T00:00:01.000Z") },
    });
    const retry = new OutboxPublisherService(prisma, successfulDispatcher());
    expect(await retry.publishBatch(1)).toEqual({
      claimed: 1,
      published: 1,
      failed: 0,
    });
    const completed = await prisma.outboxEvent.findUniqueOrThrow({
      where: { id: event.id },
    });
    expect(completed.attempts).toBe(2);
    expect(completed.publishedAt).toBeInstanceOf(Date);
  });

  it("uses skip-locked claims so concurrent publishers deliver each event once", async () => {
    const first = await createEvent(new Date("1999-01-01T00:00:00.000Z"));
    const second = await createEvent(new Date("1999-01-02T00:00:00.000Z"));
    const delivered = new Map<string, number>();
    const dispatcher: OutboxDispatcher = {
      async dispatch(event) {
        delivered.set(event.id, (delivered.get(event.id) ?? 0) + 1);
        await new Promise((resolve) => setTimeout(resolve, 25));
      },
    };
    const publishers = [
      new OutboxPublisherService(prisma, dispatcher),
      new OutboxPublisherService(prisma, dispatcher),
    ];

    const results = await Promise.all(
      publishers.map((publisher) => publisher.publishBatch(1)),
    );
    expect(results).toEqual([
      { claimed: 1, published: 1, failed: 0 },
      { claimed: 1, published: 1, failed: 0 },
    ]);
    expect(delivered.get(first.id)).toBe(1);
    expect(delivered.get(second.id)).toBe(1);
  });

  function successfulDispatcher(): OutboxDispatcher {
    return { dispatch: () => Promise.resolve() };
  }

  function createEvent(occurredAt: Date) {
    const id = randomUUID();
    return prisma.outboxEvent.create({
      data: {
        id,
        aggregateType: "IntegrationTest",
        aggregateId: id,
        eventType: "integration.test",
        payload: { id },
        occurredAt,
        nextAttemptAt: new Date("1990-01-01T00:00:00.000Z"),
      },
    });
  }
});
