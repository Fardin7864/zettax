CREATE TABLE "contract_price_observations" (
  "source" VARCHAR(100) NOT NULL,
  "timestamp" TIMESTAMP(3) NOT NULL,
  "price" DECIMAL(36,18) NOT NULL CHECK ("price" > 0),
  "payload" JSONB NOT NULL,
  "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY ("source", "timestamp")
);
CREATE FUNCTION prevent_contract_price_rewrite() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Contract price observations are immutable';
END;
$$;
CREATE TRIGGER immutable_contract_price BEFORE UPDATE OR DELETE ON contract_price_observations
FOR EACH ROW EXECUTE FUNCTION prevent_contract_price_rewrite();
