import { Inject, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { randomUUID } from "node:crypto";
import {
  OUTBOX_DISPATCHER,
  type OutboxDispatcher,
  type OutboxDispatchEvent,
} from "./outbox-dispatcher";
import { PrismaService } from "./prisma.service";

type ClaimedEvent = OutboxDispatchEvent & { attempts: number };

@Injectable()
export class OutboxPublisherService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(OUTBOX_DISPATCHER) private readonly dispatcher: OutboxDispatcher,
  ) {}

  async publishBatch(
    requestedLimit = 50,
  ): Promise<{ claimed: number; published: number; failed: number }> {
    const limit = Math.max(1, Math.min(100, Math.trunc(requestedLimit)));
    const claimToken = randomUUID();
    const events = await this.claim(limit, claimToken);
    let published = 0;
    let failed = 0;
    for (const event of events) {
      try {
        await this.dispatcher.dispatch({
          id: event.id,
          aggregateType: event.aggregateType,
          aggregateId: event.aggregateId,
          eventType: event.eventType,
          payload: event.payload,
          occurredAt: event.occurredAt,
        });
        const result = await this.prisma.outboxEvent.updateMany({
          where: { id: event.id, claimToken, publishedAt: null },
          data: {
            publishedAt: new Date(),
            claimToken: null,
            claimedAt: null,
            lastError: null,
          },
        });
        published += result.count;
      } catch (error) {
        const result = await this.prisma.outboxEvent.updateMany({
          where: { id: event.id, claimToken, publishedAt: null },
          data: {
            claimToken: null,
            claimedAt: null,
            nextAttemptAt: new Date(
              Date.now() + this.retryDelayMs(event.attempts),
            ),
            lastError: this.safeErrorName(error),
          },
        });
        failed += result.count;
      }
    }
    return { claimed: events.length, published, failed };
  }

  private claim(limit: number, claimToken: string): Promise<ClaimedEvent[]> {
    return this.prisma.$transaction((tx) =>
      tx.$queryRaw<ClaimedEvent[]>(Prisma.sql`
        WITH candidates AS (
          SELECT id
            FROM outbox_events
           WHERE published_at IS NULL
             AND next_attempt_at <= CURRENT_TIMESTAMP
             AND (claimed_at IS NULL OR claimed_at < CURRENT_TIMESTAMP - INTERVAL '2 minutes')
           ORDER BY occurred_at ASC, id ASC
           FOR UPDATE SKIP LOCKED
           LIMIT ${limit}
        )
        UPDATE outbox_events AS event
           SET claim_token = ${claimToken}::uuid,
               claimed_at = CURRENT_TIMESTAMP,
               attempts = event.attempts + 1
          FROM candidates
         WHERE event.id = candidates.id
        RETURNING event.id,
                  event.aggregate_type AS "aggregateType",
                  event.aggregate_id AS "aggregateId",
                  event.event_type AS "eventType",
                  event.payload,
                  event.occurred_at AS "occurredAt",
                  event.attempts
      `),
    );
  }

  private retryDelayMs(attempts: number): number {
    return Math.min(3_600_000, 1_000 * 2 ** Math.min(attempts, 11));
  }

  private safeErrorName(error: unknown): string {
    const name = error instanceof Error ? error.name : "UnknownError";
    return `Delivery failed (${name.slice(0, 80)})`;
  }
}
