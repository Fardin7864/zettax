CREATE TYPE "PredictionCondition" AS ENUM ('ABOVE', 'BELOW');
CREATE TYPE "PredictionSide" AS ENUM ('YES', 'NO');
CREATE TYPE "PredictionQuestionStatus" AS ENUM ('OPEN', 'SETTLED', 'CANCELLED');
CREATE TYPE "PredictionPositionResult" AS ENUM ('PENDING', 'WON', 'LOST', 'REFUNDED');

CREATE TABLE "prediction_questions" (
  "id" UUID NOT NULL,
  "creator_id" UUID,
  "instrument_id" UUID NOT NULL,
  "condition" "PredictionCondition" NOT NULL,
  "target_price" DECIMAL(30,12) NOT NULL,
  "reference_price" DECIMAL(30,12) NOT NULL,
  "reference_source" TEXT NOT NULL,
  "reference_timestamp" TIMESTAMP(3) NOT NULL,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "status" "PredictionQuestionStatus" NOT NULL DEFAULT 'OPEN',
  "outcome" "PredictionSide",
  "settlement_price" DECIMAL(30,12),
  "settlement_source" TEXT,
  "settlement_timestamp" TIMESTAMP(3),
  "yes_demo_pool" DECIMAL(24,8) NOT NULL DEFAULT 0,
  "no_demo_pool" DECIMAL(24,8) NOT NULL DEFAULT 0,
  "yes_real_pool" DECIMAL(24,8) NOT NULL DEFAULT 0,
  "no_real_pool" DECIMAL(24,8) NOT NULL DEFAULT 0,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "prediction_questions_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "prediction_questions_status_expires_at_idx" ON "prediction_questions"("status", "expires_at");
CREATE INDEX "prediction_questions_created_at_id_idx" ON "prediction_questions"("created_at" DESC, "id" DESC);
CREATE INDEX "prediction_questions_creator_id_status_idx" ON "prediction_questions"("creator_id", "status");
ALTER TABLE "prediction_questions" ADD CONSTRAINT "prediction_questions_creator_id_fkey"
  FOREIGN KEY ("creator_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "prediction_questions" ADD CONSTRAINT "prediction_questions_instrument_id_fkey"
  FOREIGN KEY ("instrument_id") REFERENCES "instruments"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE "prediction_positions" (
  "id" UUID NOT NULL,
  "question_id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "account_id" UUID NOT NULL,
  "mode" "AccountMode" NOT NULL,
  "side" "PredictionSide" NOT NULL,
  "stake" DECIMAL(24,8) NOT NULL,
  "payout_amount" DECIMAL(24,8),
  "result" "PredictionPositionResult" NOT NULL DEFAULT 'PENDING',
  "idempotency_key" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "settled_at" TIMESTAMP(3),
  CONSTRAINT "prediction_positions_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "prediction_positions_user_id_idempotency_key_key" ON "prediction_positions"("user_id", "idempotency_key");
CREATE INDEX "prediction_positions_question_id_mode_side_idx" ON "prediction_positions"("question_id", "mode", "side");
CREATE INDEX "prediction_positions_user_id_created_at_idx" ON "prediction_positions"("user_id", "created_at" DESC);
ALTER TABLE "prediction_positions" ADD CONSTRAINT "prediction_positions_question_id_fkey"
  FOREIGN KEY ("question_id") REFERENCES "prediction_questions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "prediction_positions" ADD CONSTRAINT "prediction_positions_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "prediction_positions" ADD CONSTRAINT "prediction_positions_account_id_user_id_fkey"
  FOREIGN KEY ("account_id", "user_id") REFERENCES "accounts"("id", "user_id") ON DELETE RESTRICT ON UPDATE CASCADE;
