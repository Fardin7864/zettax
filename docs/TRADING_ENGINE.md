# Normal Trading Engine

## Display market data versus execution

`GET /api/v1/markets/instruments/:instrumentId/candles` returns normalized chart candles from allowlisted server-side adapters. Binance Public Spot supplies single-venue crypto candles, Frankfurter/ECB supplies keyless daily forex reference history, and Twelve Data can supply configured multi-asset data. A free or individual Twelve Data credential is development/evaluation-only; commercial external display requires contractually sufficient business/display/redistribution rights and any applicable exchange licences. Keyless access likewise does not replace provider-terms and jurisdiction review. Requests use bounded intervals and limits, short timeouts, caching, and stable failure codes. Provider API keys remain on the server.

Display prices are never treated as proof of execution. Every response sets `executionPrice: false` and `executionEligible: false`; `DISPLAY_LIVE` is a dataset classification rather than a latency SLA or consolidated best bid/offer. Real orders must receive independently validated quotes and fills from an approved `ExecutionProvider` after the compliance gates are satisfied.

The demo engine will consume the same normalized quote stream for every user. Market buys execute from ask and sells from bid, with configuration-driven spread, commission, and neutral slippage. Commands require an idempotency key and create orders, executions, positions, ledger activity, and audit evidence atomically where appropriate. Real orders route only through a separately approved `ExecutionProvider`; PrimeVest never fabricates a provider fill.

## Execution provider boundary

`ExecutionProvider` defines instrument validation, trading status, place/cancel/get order, executions, positions, and reconciliation. `ExecutionProviderService` is the sole selection boundary:

- demo accounts resolve to `MockExecutionProvider`;
- real accounts first require `PRODUCTION_APPROVED`, the global real-trading flag, and the asset-class flag;
- the mock provider can never accept a real account;
- an unknown configured provider is rejected rather than assumed to exist;
- a production adapter must be added as an isolated, reviewed implementation after an authorized provider is selected.

The current mock implementation is deterministic and idempotent by `clientOrderId`. It is simulation infrastructure, not a broker, exchange, liquidity venue, or proof of execution.
