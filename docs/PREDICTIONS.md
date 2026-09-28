# Predictions

## Scope and safety

The web page is `/predictions`; the native app exposes Predictions in its main menu. Both use the same authenticated API, demo USD wallet, questions, positions, results and notifications. Real-money prediction participation remains disabled by the existing compliance gates. Publishing a question does not represent a guaranteed forecast.

Questions have immutable market, condition, target and expiry. Users can publish crypto questions 10 minutes to 30 days ahead, with at most five open questions per creator. Price targets must be within the permitted range of a verified reference price. Only supported, enabled instruments with verified price sources are accepted.

## Automatic questions

The financial worker maintains up to 36 active automatic questions: three templates across BTC, ETH, SOL, XRP, BCH, ADA, DOGE, AVAX, LINK, LTC, DOT and SUI.

| Template | Verified target anchor | Condition | Expiry horizon |
| --- | --- | --- | --- |
| Next hour | Price at creation | Above | Next full hour plus one hour |
| Hourly reclaim | Price one hour before creation | Above | Next full hour plus four hours |
| Daily level | Price 24 hours before creation | Below | Next full hour plus 24 hours |

Every automatic question records its source, actual anchor timestamp, price and explanation. Unavailable or invalid sources are skipped; prices are never fabricated. Generation is asynchronous so historical lookups do not block normal trade settlement. Unique template/hour keys prevent duplicate generation, including immediately after an administrative cancellation.

These are objective future-price questions anchored to historical observations, not probability models or investment recommendations. Pool percentages describe participants' stake distribution, not a statistically estimated chance of winning. Targets display the instrument's precision rather than rounding every market to two decimals.

## Funds and settlement

Participation locks demo USD immediately. Users can add to the same side but cannot join the opposing side of the same question or cash out early. Idempotent command keys and serializable database transactions protect against duplicate requests and concurrent overspending.

The verified expiry price determines the outcome: ABOVE and BELOW are strict comparisons; equality resolves NO. The zero-fee pool is shared proportionally among winning stakes, with integer-cent allocation conserving the entire pool. If there are no winning stakes, participants receive refunds. A winning stake with no opposing stake still has a WON result even though its return equals its stake.

Unavailable expiry data leaves a question awaiting a result. The worker retries with a delay, without starving other questions. After 24 hours without verifiable settlement data, the question is cancelled and all pending stakes are refunded. Admin cancellation also refunds atomically; replay cannot refund twice. Settled questions cannot be cancelled.

Ledger entries, wallet updates, durable personal events and persistent result notifications are written transactionally. App/web reconnect and periodic reconciliation recover missed realtime updates. Client pending commands persist their original idempotency key for safe retry after a network interruption.

## Administration

The admin Predictions section provides paginated questions, reports and positions, creation, audited cancellation/refunds, settlement retry, report resolution and creator restrictions. Admin routes retain role/permission checks. Public user routes cannot proxy administrative commands.

## Verification and deployment

Deployment on 2026-09-28 used the additive `20260928093000_prediction_experience` migration, with a private database backup taken first. API, worker, web and admin run from `/srv/zettax/releases/20260928-predictions`. The prior release is preserved for recovery. Public Play publishing remains on hold; the USB development app is updated independently.

Verification completed:

- Backend suite: 140 passed; database-dependent cases are separately gated.
- Four prediction PostgreSQL integration tests passed in a disposable isolated schema, covering concurrent stake idempotency, overspending protection, settlement and question creation.
- Flutter suite: 78 passed; analyzer found no issues.
- Browser tests cover responsive cards/details, persistent navbar download visibility, sign-in gating and low-price target precision.
- Live API readiness, verified automatic questions, website charts and USB app rendering checked.

Useful commands, from the repository root unless noted:

```powershell
pnpm --filter @primevest/backend test
pnpm --filter @primevest/web exec playwright test e2e/predictions.spec.ts --workers=1
# Run in apps/mobile:
flutter test
flutter analyze
```

The browser suite expects the web development server on port 3002 (or `PREDICTION_TEST_URL`). PostgreSQL integration tests require `RUN_PREDICTION_INTEGRATION=true` and a dedicated migrated test schema; never run fixtures against production user data.
