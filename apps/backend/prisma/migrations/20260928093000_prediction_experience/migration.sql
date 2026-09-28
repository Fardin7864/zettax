ALTER TABLE "users" ADD COLUMN "prediction_creation_enabled" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "prediction_questions"
  ADD COLUMN "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "participant_count" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "cancellation_reason" TEXT,
  ADD COLUMN "cancelled_at" TIMESTAMP(3);
ALTER TABLE "prediction_questions" ADD COLUMN "client_request_key" TEXT;
ALTER TABLE "prediction_questions" ADD COLUMN "system_template_key" TEXT, ADD COLUMN "generation_context" JSONB;
ALTER TABLE "prediction_questions" ADD COLUMN "next_settlement_at" TIMESTAMP(3), ADD COLUMN "last_settlement_error" TEXT;
CREATE UNIQUE INDEX "prediction_questions_system_template_key_key" ON "prediction_questions"("system_template_key");
CREATE UNIQUE INDEX "prediction_questions_creator_id_client_request_key_key" ON "prediction_questions"("creator_id", "client_request_key");
UPDATE "prediction_questions" q SET "participant_count" = (SELECT COUNT(DISTINCT "user_id") FROM "prediction_positions" p WHERE p."question_id" = q."id");
CREATE TABLE "prediction_reports" (
  "id" UUID PRIMARY KEY,
  "question_id" UUID NOT NULL REFERENCES "prediction_questions"("id") ON DELETE RESTRICT,
  "reporter_id" UUID NOT NULL,
  "reason" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'OPEN',
  "resolution_note" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "resolved_at" TIMESTAMP(3)
);
CREATE UNIQUE INDEX "prediction_reports_question_id_reporter_id_key" ON "prediction_reports"("question_id", "reporter_id");
CREATE INDEX "prediction_reports_status_created_at_idx" ON "prediction_reports"("status", "created_at");
