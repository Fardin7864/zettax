ALTER TABLE "users"
  ALTER COLUMN "phone" DROP NOT NULL,
  ALTER COLUMN "password_hash" DROP NOT NULL;

CREATE TYPE "IdentityProvider" AS ENUM ('GOOGLE');

CREATE TABLE "external_identities" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "provider" "IdentityProvider" NOT NULL,
  "provider_subject" VARCHAR(255) NOT NULL,
  "provider_email" VARCHAR(320),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "external_identities_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "external_identities_provider_provider_subject_key"
  ON "external_identities"("provider", "provider_subject");
CREATE INDEX "external_identities_user_id_idx"
  ON "external_identities"("user_id");

ALTER TABLE "external_identities"
  ADD CONSTRAINT "external_identities_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
