ALTER TABLE "users" ADD COLUMN "community_rules_version" TEXT, ADD COLUMN "community_rules_accepted_at" TIMESTAMP(3);
ALTER TABLE "community_posts" ADD COLUMN "hidden_at" TIMESTAMP(3);
ALTER TABLE "community_comments" ADD COLUMN "hidden_at" TIMESTAMP(3);
CREATE TABLE "community_blocks" (
 "blocker_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
 "blocked_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
 "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY ("blocker_id", "blocked_id"),
 CONSTRAINT "community_blocks_not_self" CHECK ("blocker_id" <> "blocked_id")
);
CREATE INDEX "community_blocks_blocked_id_idx" ON "community_blocks"("blocked_id");
CREATE TABLE "community_reports" (
 "id" UUID NOT NULL PRIMARY KEY,
 "reporter_id" UUID NOT NULL REFERENCES "users"("id") ON DELETE CASCADE,
 "target_type" TEXT NOT NULL CHECK ("target_type" IN ('POST','COMMENT','USER')),
 "target_id" UUID NOT NULL,
 "reason" VARCHAR(1000) NOT NULL,
 "status" TEXT NOT NULL DEFAULT 'OPEN' CHECK ("status" IN ('OPEN','HIDDEN','DISMISSED')),
 "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 "reviewed_at" TIMESTAMP(3), "reviewed_by" UUID
);
CREATE UNIQUE INDEX "community_reports_reporter_id_target_type_target_id_key" ON "community_reports"("reporter_id","target_type","target_id");
CREATE INDEX "community_reports_status_created_at_idx" ON "community_reports"("status","created_at");
ALTER TABLE "users" ADD COLUMN "community_posting_disabled" BOOLEAN NOT NULL DEFAULT false;
INSERT INTO "permissions" ("id","key","description") VALUES ('c0000000-0000-4000-8000-000000000001','community.moderate','Review community reports and hide abusive content') ON CONFLICT ("key") DO NOTHING;
