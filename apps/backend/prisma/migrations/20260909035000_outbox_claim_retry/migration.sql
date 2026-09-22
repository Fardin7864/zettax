ALTER TABLE outbox_events
  ADD COLUMN claim_token UUID,
  ADD COLUMN claimed_at TIMESTAMP(3),
  ADD COLUMN next_attempt_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE outbox_events
  ADD CONSTRAINT outbox_events_claim_pair CHECK (
    (claim_token IS NULL AND claimed_at IS NULL) OR
    (claim_token IS NOT NULL AND claimed_at IS NOT NULL)
  );

DROP INDEX outbox_events_published_at_occurred_at_idx;
CREATE INDEX outbox_events_published_at_next_attempt_at_claimed_at_occurred_at_idx
  ON outbox_events(published_at, next_attempt_at, claimed_at, occurred_at);
