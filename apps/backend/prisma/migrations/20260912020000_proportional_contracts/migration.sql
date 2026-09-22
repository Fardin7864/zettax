ALTER TABLE timed_contracts ADD COLUMN settlement_model TEXT NOT NULL DEFAULT 'FIXED_PAYOUT_V1';
ALTER TABLE timed_contracts ADD COLUMN profit_fee_rate DECIMAL(8,6) NOT NULL DEFAULT 0;
ALTER TABLE timed_contract_settlements ADD COLUMN gross_pnl DECIMAL(24,8) NOT NULL DEFAULT 0;
ALTER TABLE timed_contract_settlements ADD COLUMN fee_amount DECIMAL(24,8) NOT NULL DEFAULT 0;
ALTER TABLE timed_contracts ADD CONSTRAINT contract_fee_range CHECK (profit_fee_rate >= 0 AND profit_fee_rate <= 1);
INSERT INTO system_config (key, value, updated_at)
VALUES ('trading.profitFeeRate', '"0"'::jsonb, NOW()) ON CONFLICT (key) DO NOTHING;
