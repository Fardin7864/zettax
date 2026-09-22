# Compliance Gates

`COMPLIANCE_MODE` is one of `DEMO_ONLY`, `SANDBOX`, or `PRODUCTION_APPROVED`. The default and any invalid/missing value resolves to `DEMO_ONLY`.

Real-money activity requires all of the following:

1. `COMPLIANCE_MODE=PRODUCTION_APPROVED`;
2. the global `ENABLE_REAL_TRADING` gate;
3. the product gate for its asset class or timed trading;
4. an enabled real account and instrument;
5. an approved, healthy execution provider;
6. KYC, age, risk, jurisdiction and account controls;
7. current disclosure acceptance and any required step-up authentication.

Deposits and withdrawals independently require `PRODUCTION_APPROVED` plus their feature gate. `SANDBOX` can exercise adapters only against non-cash/non-production provider environments. Timed real trading remains unavailable until a specific lawful product and authorized provider are approved.

The execution registry contains only `MockExecutionProvider` today. It declares `supportsRealMoney=false` and rejects every non-demo order. Setting `EXECUTION_PROVIDER` to an arbitrary string does not register an adapter: the backend returns `PROVIDER_UNAVAILABLE`. This prevents configuration flags from fabricating a production integration.

In a production process, `PRODUCTION_APPROVED` additionally requires non-empty `PRODUCTION_APPROVAL_REFERENCE` and `EXECUTION_PROVIDER_APPROVAL_REFERENCE`. These references are evidence hooks, not substitutes for review. The release approval record must identify the regulator/legal opinion, approved products and jurisdictions, provider contract/account, credential owner, KYC/AML controls, customer disclosures, reconciliation owner, incident response, and rollback authority.

The mobile/admin UI may hide unavailable controls, but hiding is not a security control. Backend services reject forbidden commands using stable codes such as `REAL_TRADING_NOT_APPROVED`, `DEPOSIT_DISABLED`, `WITHDRAWAL_DISABLED`, or `TIMED_TRADING_DISABLED`.
