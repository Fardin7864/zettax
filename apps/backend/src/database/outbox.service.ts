import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";

@Injectable()
export class OutboxService {
  enqueue(
    tx: Prisma.TransactionClient,
    input: {
      aggregateType: string;
      aggregateId: string;
      eventType: string;
      payload: Prisma.InputJsonValue;
    },
  ) {
    return tx.outboxEvent.create({ data: input, select: { id: true } });
  }

  async enqueueAccount(
    tx: Prisma.TransactionClient,
    userId: string,
    input: {
      aggregateType: string;
      aggregateId: string;
      eventType: string;
      payload: Prisma.InputJsonValue;
    },
  ) {
    const stream = await tx.accountEventStream.upsert({
      where: { userId },
      create: { userId, lastSequence: 1n },
      update: { lastSequence: { increment: 1 } },
      select: { lastSequence: true },
    });
    const [accountEvent, outboxEvent] = await Promise.all([
      tx.accountEvent.create({
        data: {
          userId,
          sequence: stream.lastSequence,
          eventType: input.eventType,
          payload: input.payload,
        },
        select: { id: true, sequence: true },
      }),
      this.enqueue(tx, input),
    ]);
    return { accountEvent, outboxEvent };
  }
}
