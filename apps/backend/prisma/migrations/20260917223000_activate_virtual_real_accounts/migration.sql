-- Ensure every existing user can select the virtual REAL-labelled account.
-- This migration creates no money: all new wallets start at zero.
INSERT INTO accounts (id, user_id, mode, status, created_at)
SELECT gen_random_uuid(), u.id, 'REAL'::"AccountMode", 'ACTIVE'::"AccountStatus", CURRENT_TIMESTAMP
FROM users u
WHERE NOT EXISTS (
  SELECT 1 FROM accounts a WHERE a.user_id = u.id AND a.mode = 'REAL'::"AccountMode"
);

INSERT INTO wallets (id, account_id, currency_code, available_projection, locked_projection, updated_at)
SELECT gen_random_uuid(), a.id, 'BDT', 0, 0, CURRENT_TIMESTAMP
FROM accounts a
WHERE a.mode = 'REAL'::"AccountMode"
  AND NOT EXISTS (
    SELECT 1 FROM wallets w WHERE w.account_id = a.id AND w.currency_code = 'BDT'
  );
