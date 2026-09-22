CREATE TYPE "PaymentAccountType" AS ENUM ('PERSONAL', 'AGENT');

ALTER TABLE "payment_methods"
ADD COLUMN "account_type" "PaymentAccountType" NOT NULL DEFAULT 'PERSONAL';

INSERT INTO "payment_methods" (
  "id",
  "type",
  "display_name",
  "account_number",
  "account_type",
  "instructions",
  "minimum_deposit",
  "maximum_deposit",
  "fee_type",
  "fee_value",
  "is_enabled"
)
VALUES
  (
    '20000000-0000-4000-8000-000000000001',
    'BKASH',
    'bKash',
    '01885482244',
    'PERSONAL',
    'Send Money to this personal bKash number, then submit the exact amount, sender number, transaction ID, and payment screenshot.',
    100.00,
    100000.00,
    'NONE',
    0,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'NAGAD',
    'Nagad',
    '01885482244',
    'PERSONAL',
    'Send Money to this personal Nagad number, then submit the exact amount, sender number, transaction ID, and payment screenshot.',
    100.00,
    100000.00,
    'NONE',
    0,
    true
  ),
  (
    '20000000-0000-4000-8000-000000000003',
    'ROCKET',
    'Rocket',
    '01885482244',
    'PERSONAL',
    'Send Money to this personal Rocket number, then submit the exact amount, sender number, transaction ID, and payment screenshot.',
    100.00,
    100000.00,
    'NONE',
    0,
    true
  )
ON CONFLICT ("id") DO UPDATE SET
  "display_name" = EXCLUDED."display_name",
  "account_number" = EXCLUDED."account_number",
  "account_type" = EXCLUDED."account_type",
  "instructions" = EXCLUDED."instructions",
  "minimum_deposit" = EXCLUDED."minimum_deposit",
  "maximum_deposit" = EXCLUDED."maximum_deposit",
  "fee_type" = EXCLUDED."fee_type",
  "fee_value" = EXCLUDED."fee_value",
  "is_enabled" = EXCLUDED."is_enabled";
