-- Idempotency keys are endpoint/operation scoped by idempotency_commands.
-- Keeping a user-wide unique constraint on orders prevents a valid close from
-- reusing a key used for a different operation.
DROP INDEX "orders_user_id_idempotency_key_key";
CREATE INDEX "orders_user_id_idempotency_key_idx"
  ON "orders"("user_id", "idempotency_key");
