CREATE TABLE "account_event_streams" (
    "user_id" UUID NOT NULL,
    "last_sequence" BIGINT NOT NULL DEFAULT 0,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "account_event_streams_pkey" PRIMARY KEY ("user_id")
);

CREATE TABLE "account_events" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "sequence" BIGINT NOT NULL,
    "event_type" VARCHAR(160) NOT NULL,
    "payload" JSONB NOT NULL,
    "occurred_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "account_events_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "account_events_user_id_sequence_key"
ON "account_events"("user_id", "sequence");
CREATE INDEX "account_events_user_id_occurred_at_idx"
ON "account_events"("user_id", "occurred_at");

ALTER TABLE "account_event_streams"
ADD CONSTRAINT "account_event_streams_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "account_events"
ADD CONSTRAINT "account_events_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
