# Market-Data Operations

## Scope and safety boundary

PrimeVest market candles are informational display data. They are not broker quotes, a consolidated market view, proof of asset ownership, or evidence that an instrument is legally tradeable in Bangladesh. The REST response always sets `executionPrice: false`. Market-data availability does not enable deposits, withdrawals, real orders, or timed real-money contracts.

Real execution remains disabled unless every compliance gate passes and a separately approved `ExecutionProvider` supplies executable quotes, fills, and reconciliation. Never feed a display candle directly into a real-money settlement path.

## Provider matrix

| Asset path                                           | Adapter behavior                                                                   | Credential                                                               | Freshness contract                                                    | Production condition                                                                                                                                                    |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Crypto                                               | Binance public Spot REST history plus shared kline WebSocket for allowlisted pairs | None                                                                     | `DISPLAY_LIVE` dataset class; one venue, network/cache delay possible | Review current Binance terms, territorial availability, display/redistribution rights, attribution, connection limits, and rate limits                                  |
| Forex fallback                                       | Frankfurter daily history filtered to ECB data                                     | None                                                                     | `REFERENCE_DAILY`; intraday requests return `effectiveInterval: 1d`   | Treat as reference data, review Frankfurter and underlying ECB/source terms, and never represent it as executable FX                                                    |
| Stocks, indices, commodities, higher-frequency forex | Twelve Data `/time_series`                                                         | `TWELVE_DATA_API_KEY` plus environment-scoped display-rights attestation | `DELAYED` in the PrimeVest contract                                   | Development/evaluation with a free or individual plan only; client-facing commercial use requires suitable business/display/redistribution rights and exchange licences |
| Offline mobile fallback                              | Deterministic PrimeVest simulator                                                  | None                                                                     | `SIMULATED`                                                           | Demo-only and visibly labelled; never call it live or real market data                                                                                                  |

Provider names describe provenance, not endorsement or partnership. Availability, coverage, latency, and terms can change. Operations must review the current official documentation and agreements before every production provider change.

Official references reviewed on 8 September 2026:

- [Binance Spot REST API](https://developers.binance.com/en/docs/products/spot/rest-api) recommends the market-data-only endpoint and documents IP request-weight limits and mandatory backoff for HTTP 429.
- [Frankfurter source and licence](https://github.com/lineofflight/frankfurter) documents the free public API and MIT-licensed software. That software licence does not automatically replace review of underlying institutional data terms.
- [Twelve Data credits](https://support.twelvedata.com/en/articles/5615854-credits) documents credit consumption, daily Basic-plan limits, HTTP 429, and quota reset behavior.
- [Twelve Data commercial and personal usage](https://support.twelvedata.com/en/articles/5332349-commercial-and-personal-usage) distinguishes individual development/internal use from business commercial display and redistribution.
- [Twelve Data attribution](https://support.twelvedata.com/en/articles/12647398-attribution-guidelines-for-using-twelve-data) requires visible attribution for externally displayed data unless the governing contract says otherwise.
- [Twelve Data terms](https://twelvedata.com/terms) govern permitted caching, commercial use, redistribution, third-party exchange terms, and credential handling.

## Configuration and secret handling

Set an optional key in the root `.env` file:

```dotenv
TWELVE_DATA_API_KEY=replace-with-development-key
TWELVE_DATA_DISPLAY_LICENSE_APPROVED=false
TWELVE_DATA_REQUESTS_PER_MINUTE=8
MARKET_DATA_CACHE_MAX_ENTRIES=500
```

`docker-compose.yml` passes these settings only to `backend`. The mobile and admin clients call PrimeVest's API and must never receive the upstream credential. Do not place the key in source control, logs, screenshots, crash reports, `NEXT_PUBLIC_*` variables, APK assets, or Dart defines.

`TWELVE_DATA_DISPLAY_LICENSE_APPROVED=true` is an explicit operator attestation that the configured credential and intended display are permitted in that environment. Keep it `false` by default. It is independent of `COMPLIANCE_MODE`, cannot enable execution, and does not convert a development/free plan into commercial display rights. `TWELVE_DATA_REQUESTS_PER_MINUTE` applies a backend quota below or equal to the contracted allowance; `MARKET_DATA_CACHE_MAX_ENTRIES` bounds process memory used by candle caching.

Local default behavior with an empty key:

- crypto candles use the keyless Binance public endpoint;
- forex candles use daily Frankfurter/ECB reference history;
- stocks, indices, commodities, and non-reference forex data remain unavailable until both the key and display-rights attestation are configured;
- the offline mobile demo may explicitly fall back to simulated data.

The backend accepts candle requests from 10–200 records, rejects values outside that range before provider access, uses an eight-second upstream timeout, coalesces concurrent identical requests, and caches by provider, instrument, interval, and limit. Current cache lifetimes are 10 seconds for `DISPLAY_LIVE`, 60 seconds for `DELAYED`, and one hour for `REFERENCE_DAILY`. Cache duration must remain within each provider contract; production terms take precedence over these defaults.

## Freshness and failure semantics

The client must display the returned provider and data classification. It must compare `requestedInterval` and `effectiveInterval`; a `1h` request served by the daily forex fallback is not an hourly chart. `providerTimestamp` is the newest upstream observation used, `receivedAt` records when PrimeVest normalized the response, and each candle's `openTime` and `closeTime` describe its time bucket. `isSyntheticOhlc=true` means reference-rate observations were expanded deterministically for chart rendering, not that intraday OHLC trading occurred. Both `executionPrice` and `executionEligible` remain `false`.

Current stable failures are:

| Code                           | HTTP | Meaning                                                   | Client behavior                                                          |
| ------------------------------ | ---: | --------------------------------------------------------- | ------------------------------------------------------------------------ |
| `INSTRUMENT_NOT_FOUND`         |  404 | Instrument is not allowlisted                             | Stop retrying; return to instrument selection                            |
| `UNSUPPORTED_INTERVAL`         |  400 | Interval is outside the contract                          | Stop retrying; select a supported interval                               |
| `INVALID_CANDLE_LIMIT`         |  400 | Limit is not an integer from 10 through 200               | Stop retrying; correct the request                                       |
| `MARKET_DATA_KEY_REQUIRED`     |  503 | Required provider credential is absent                    | Show unavailable or explicitly simulated demo data                       |
| `MARKET_DATA_LICENSE_REQUIRED` |  503 | Environment display-rights attestation is absent          | Do not call Twelve Data; operator must verify rights before enabling it  |
| `MARKET_DATA_RATE_LIMITED`     |  503 | PrimeVest or the upstream provider has throttled requests | Back off with jitter and retain only visibly stale data                  |
| `MARKET_DATA_UNAVAILABLE`      |  503 | Timeout, upstream error, or malformed/empty payload       | Back off; retain the last chart only when it has an explicit stale label |

Never silently relabel cached, delayed, daily-reference, or simulated data as live. Never retry HTTP 429 in a tight loop. Use bounded exponential backoff with jitter and honor provider `Retry-After` guidance when it is exposed through the adapter.

## Monitoring and release gates

Production monitoring should record provider, instrument, effective interval, request latency, success/failure code, cache hit ratio, data age, rate-limit headroom, and consecutive failures. Logs must not contain API keys or full upstream URLs containing credentials. Alert on sustained unavailability, excessive data age, schema failures, quota exhaustion, or unexpected provider changes.

Before a client-facing release:

1. Confirm `/health` and `/ready` are healthy without exposing provider secrets.
2. Request crypto candles and verify ascending times, decimal strings, provider ID/name/source symbol, requested/effective interval, provider timestamp, freshness, `isSyntheticOhlc`, `executionPrice: false`, and `executionEligible: false`.
3. With no Twelve Data key, verify a stock request fails with `MARKET_DATA_KEY_REQUIRED` and forex returns daily reference data.
4. With a key but no display-rights attestation, verify non-reference Twelve Data requests fail with `MARKET_DATA_LICENSE_REQUIRED`.
5. With a permitted development key and environment attestation, verify stock, index, commodity, and forex symbols against the subscribed coverage and quota.
6. Exceed the configured local request allowance and simulate upstream HTTP 429; verify `MARKET_DATA_RATE_LIMITED`, bounded retry behavior, and no API-key leakage.
7. Simulate timeout, malformed payload, empty series, and upstream 4xx/5xx; verify sanitized `MARKET_DATA_UNAVAILABLE` responses and no backend crash.
8. Verify limits below 10 and above 200 and unsupported intervals fail before an upstream request.
9. Verify provider credentials are absent from API responses, logs, web bundles, APK contents, and error telemetry.
10. Verify the app labels provider/freshness and visibly distinguishes simulated fallback.
11. Verify repeated requests use backend caching and do not create one external connection/request per phone.
12. Reconfirm all real-money flags remain disabled and the mock execution provider rejects real accounts.
13. Authenticate a `/market` Socket.IO connection, subscribe to a crypto
    interval, verify strictly increasing sequence values and both execution
    flags remain false, then interrupt the provider connection and verify
    bounded reconnect plus REST snapshot recovery.
14. Verify an absent/expired access token is disconnected and unsupported asset
    classes return `REALTIME_CAPABILITY_UNAVAILABLE` without starting an
    upstream stream.
15. For production display, attach the provider contract, display/redistribution permission, attribution implementation, exchange approvals, retention rules, quota plan, and approval owner to the release record.

Automated unit tests cover REST provider normalization, realtime kline
normalization, client safety flags, the keyless forex fallback, missing-key
behavior, unknown instruments, and unsupported intervals. Integration tests
with live upstream services should be opt-in because network availability and
quotas are nondeterministic; release smoke tests must record timestamps and
provider responses without recording credentials.
