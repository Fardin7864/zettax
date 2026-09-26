ALTER TABLE "user_security"
  ADD COLUMN "pending_totp_secret" TEXT,
  ADD COLUMN "last_totp_counter" BIGINT,
  ADD COLUMN "email_code_hash" TEXT,
  ADD COLUMN "email_code_expires_at" TIMESTAMP(3),
  ADD COLUMN "email_code_sent_at" TIMESTAMP(3),
  ADD COLUMN "email_code_attempts" INTEGER NOT NULL DEFAULT 0;
