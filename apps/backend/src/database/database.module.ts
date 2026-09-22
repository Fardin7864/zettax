import { Global, Module } from "@nestjs/common";
import { PrismaService } from "./prisma.service";
import { IdempotencyService } from "./idempotency.service";
import { LedgerService } from "./ledger.service";
import { OutboxService } from "./outbox.service";
import {
  DurableOnlyOutboxDispatcher,
  OUTBOX_DISPATCHER,
} from "./outbox-dispatcher";
import { OutboxPublisherService } from "./outbox-publisher.service";

@Global()
@Module({
  providers: [
    PrismaService,
    LedgerService,
    IdempotencyService,
    OutboxService,
    OutboxPublisherService,
    DurableOnlyOutboxDispatcher,
    {
      provide: OUTBOX_DISPATCHER,
      useExisting: DurableOnlyOutboxDispatcher,
    },
  ],
  exports: [
    PrismaService,
    LedgerService,
    IdempotencyService,
    OutboxService,
    OutboxPublisherService,
  ],
})
export class DatabaseModule {}
