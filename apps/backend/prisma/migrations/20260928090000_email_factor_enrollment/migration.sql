ALTER TABLE "user_security"
  ADD COLUMN "email_enabled" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "email_code_purpose" TEXT;
