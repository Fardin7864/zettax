ALTER TABLE "community_comments"
  ADD COLUMN "parent_id" UUID,
  ADD COLUMN "reply_count" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "community_comments"
  ADD CONSTRAINT "community_comments_parent_id_fkey"
  FOREIGN KEY ("parent_id") REFERENCES "community_comments"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

DROP INDEX IF EXISTS "community_comments_post_id_created_at_idx";
CREATE INDEX "community_comments_post_id_created_at_id_idx"
  ON "community_comments"("post_id", "created_at", "id");
CREATE INDEX "community_comments_parent_id_created_at_idx"
  ON "community_comments"("parent_id", "created_at");
