import { Injectable } from "@nestjs/common";
import type { Prisma } from "@prisma/client";

export const OUTBOX_DISPATCHER = Symbol("OUTBOX_DISPATCHER");

export type OutboxDispatchEvent = {
  id: string;
  aggregateType: string;
  aggregateId: string;
  eventType: string;
  payload: Prisma.JsonValue;
  occurredAt: Date;
};

/** Implementations must tolerate duplicate delivery (at-least-once semantics). */
export interface OutboxDispatcher {
  dispatch(event: OutboxDispatchEvent): Promise<void>;
}

/** Safe default: no external delivery is claimed when no adapter is installed. */
@Injectable()
export class DurableOnlyOutboxDispatcher implements OutboxDispatcher {
  dispatch(): Promise<void> {
    return Promise.reject(new Error("OUTBOX_DISPATCHER_NOT_CONFIGURED"));
  }
}
