# PrimeVest API Contract

## Conventions

- REST base path: `/api/v1`; documentation: `/api/docs`.
- JSON uses camelCase; timestamps are ISO-8601 UTC; money and quantity are decimal strings.
- Authenticated calls use `Authorization: Bearer <access-token>`.
- Mutation requests receive/return `X-Request-ID`; financial creation additionally requires `Idempotency-Key`.
- Pagination uses opaque cursor plus bounded `limit`.
- The server supplies current time and authoritative account/compliance state.

Successful response:

```json
{
  "data": {},
  "meta": { "requestId": "uuid", "timestamp": "2026-09-07T00:00:00.000Z" }
}
```

Error response:

```json
{
  "code": "REAL_TRADING_NOT_APPROVED",
  "message": "Real trading is not available.",
  "requestId": "uuid",
  "details": {}
}
```

Messages are safe fallbacks; clients localize by stable `code`. Internal/provider errors are not exposed.

## Resource groups

| Group                              | Representative operations                                                 |
| ---------------------------------- | ------------------------------------------------------------------------- |
| `/auth`                            | register, login, refresh, logout, logout-all, recovery, verification, 2FA |
| `/users`, `/profile`               | self profile, preferences, devices, account deletion request              |
| `/accounts`, `/wallets`            | account switch, balances, transactions, demo reset                        |
| `/markets`, `/instruments`         | categories, search, quotes, candles, market status                        |
| `/watchlists`                      | list, favorite/unfavorite                                                 |
| `/orders`, `/positions`, `/trades` | create/cancel order, close demo position, history                         |
| `/timed-contracts`                 | quote terms, create, active/history, settlement evidence                  |
| `/kyc`                             | case, presigned upload, submit, status                                    |
| `/deposits`, `/withdrawals`        | enabled methods, create request, request history                          |
| `/notifications`, `/alerts`        | list/read/preferences, price alert CRUD                                   |
| `/subscriptions`                   | plans and current subscription                                            |
| `/admin/*`                         | permission-protected operations, queues, configuration and reports        |

## Financial command contract

The API validates the idempotency key, actor, object ownership, account mode, compliance gates, instrument/market state, quote freshness, decimal precision, limits, funds, fees and step-up authentication. The server returns the original result for a safely repeated key with the same request fingerprint and rejects reuse with different content.

## WebSocket contract

Socket.IO namespace `/market` requires an access token in handshake `auth.token`
and permits only allowlisted instrument/interval subscriptions. After
`market:ready`, a client sends `market:subscribe` with `instrumentId` and
`interval`. The acknowledgement either has `ok: true` or a stable code such as
`AUTH_REQUIRED`, `AUTH_SESSION_EXPIRED`, `INSTRUMENT_NOT_FOUND`,
`UNSUPPORTED_INTERVAL`, or `REALTIME_CAPABILITY_UNAVAILABLE`.

For supported crypto instruments the gateway emits `market:candle` with
`schemaVersion`, monotonically increasing `sequence`, `instrumentId`,
`interval`, provider provenance/timestamps, `final`, and one normalized OHLCV
candle. Every event explicitly contains `executionPrice: false` and
`executionEligible: false`. `market:status` reports provider connection or
reconnection state. The gateway shares one upstream Binance kline stream among
subscribers, closes it when unused, and reconnects with bounded exponential
backoff. Clients detect sequence gaps and restore an authoritative REST candle
snapshot before continuing. Other asset classes retain the REST path until an
approved realtime provider capability exists.

Socket.IO namespace `/account` requires an access token in handshake
`auth.token`. A new session receives `account:snapshot` containing owned
balances, recent orders and funding activity, open positions, pending timed
contracts, notifications, and a decimal-string `snapshotVersion`.

Clients persist the last applied sequence and reconnect with
`auth.afterSequence`. The gateway returns `account:recovery` in ascending,
per-user sequence order, then emits durable `account:event` messages. Clients
apply each sequence once and request `account:recover` after a detected gap. An
invalid or future cursor yields `ACCOUNT_SEQUENCE_INVALID` and an authoritative
snapshot. Events are inserted in the same database transaction as each
financial mutation. The gateway reads that durable stream, so recovery remains
correct across both API replicas and during a Redis outage.

## Initial endpoints

- `GET /health` — liveness, no dependency disclosure.
- `GET /ready` — readiness summary suitable for orchestration.
- `GET /api/v1/system/config` — public-safe app mode and feature availability.
- `GET /api/v1/markets/instruments` — development seed catalogue, explicitly marked simulated.
- `GET /api/v1/markets/instruments/:instrumentId/candles` — normalized, display-only candle history from a server-side provider adapter.

## Integrated account and trading slice

These resource shapes are the shared backend/mobile contract for the current
implementation track. Account-scoped routes require a bearer access token.

- `GET /api/v1/users/me` returns the authenticated identity and profile.
- `GET /api/v1/accounts` returns both account summaries. Each summary contains
  `id`, `mode`, `status`, `wallets`, `openPositionCount`, `createdAt`; wallet
  values are decimal strings: `available`, `locked`, and `equity`.
- `GET /api/v1/accounts/:mode/transactions?limit=&cursor=` returns only ledger
  activity belonging to the authenticated user's selected account and mode.
- `POST /api/v1/accounts/demo/reset` requires `Idempotency-Key`, appends a
  balanced reset journal and never changes the REAL account.
- `GET /api/v1/orders?accountMode=&status=&limit=&cursor=` lists owned orders.
- `POST /api/v1/orders` requires `Idempotency-Key` and accepts
  `accountMode`, `instrumentId`, `clientOrderId`, `side`, `orderType`,
  `quantity`, and optional `limitPrice`/`stopPrice`. It never accepts a fill
  price from the client.
- `POST /api/v1/orders/:id/cancel` requires ownership and mode validation.
- `GET /api/v1/positions?accountMode=&status=` lists owned positions with
  decimal-string quantity, entry price and realized/unrealized P/L.
- `POST /api/v1/positions/:id/close` requires `Idempotency-Key`; price evidence,
  P/L, balance effects and settlement are calculated by the server.
- `GET /api/v1/trades?accountMode=&limit=&cursor=` lists executions joined to
  their owned orders and instruments.

`accountMode=REAL` is a valid read scope even while empty. A REAL mutation is
rejected with `REAL_TRADING_NOT_APPROVED` unless compliance and an approved
real execution adapter both allow it. DEMO and REAL records are never merged in
one balance, position, history or transaction response.

## Display market-data endpoints

`GET /api/v1/markets/instruments/:instrumentId/candles` accepts:

- `interval`: `1m`, `5m`, `15m`, `30m`, `1h`, `4h`, `1d`, `1w`, or
  `1M`; defaults to `1h`.
- `limit`: integer candle count from 10 through 200; defaults to 90. Values outside the range are rejected before an upstream request.
- `before`: optional ISO-8601 UTC timestamp used as an exclusive historical
  cursor. A full page returns `nextCursor` equal to its oldest candle open time;
  clients pass that value back to load older candles.

The response payload is wrapped by the standard success envelope:

```json
{
  "data": {
    "instrumentId": "btc-usd",
    "symbol": "BTC/USD",
    "assetClass": "CRYPTO",
    "requestedInterval": "1h",
    "effectiveInterval": "1h",
    "providerId": "BINANCE_PUBLIC_SPOT",
    "provider": "Binance Public Spot",
    "sourceSymbol": "BTCUSDT",
    "freshness": "DISPLAY_LIVE",
    "providerTimestamp": "2026-09-07T23:59:59.999Z",
    "executionPrice": false,
    "executionEligible": false,
    "isSyntheticOhlc": false,
    "receivedAt": "2026-09-08T00:00:00.000Z",
    "candles": [
      {
        "openTime": "2026-09-07T23:00:00.000Z",
        "closeTime": "2026-09-07T23:59:59.999Z",
        "open": "110000.00",
        "high": "111000.00",
        "low": "109500.00",
        "close": "110500.00",
        "volume": "12.5"
      }
    ]
  },
  "meta": {
    "requestId": "uuid",
    "timestamp": "2026-09-08T00:00:00.000Z"
  }
}
```

`freshness` is a source classification, not a delivery guarantee:

- `DISPLAY_LIVE`: upstream supplies a current display feed; network, provider, and cache delay still apply.
- `DELAYED`: provider data may be delayed.
- `REFERENCE_DAILY`: daily reference history; when this fallback serves an intraday request, `effectiveInterval` is `1d`.

`isSyntheticOhlc` is `true` when reference-rate observations were deterministically expanded into chart-compatible OHLC bars; those bars are not intraday observations. `executionPrice` and `executionEligible` are always `false`. The endpoint must not be used as a fill, settlement, best-execution, or ownership record. Stable errors include `INSTRUMENT_NOT_FOUND` (404), `UNSUPPORTED_INTERVAL` (400), `INVALID_CANDLE_LIMIT` (400), `MARKET_DATA_KEY_REQUIRED` (503), `MARKET_DATA_LICENSE_REQUIRED` (503), `MARKET_DATA_RATE_LIMITED` (503), and `MARKET_DATA_UNAVAILABLE` (503). Provider credentials and raw upstream error details are never returned.

## Authentication endpoints

- `POST /api/v1/auth/register` — creates a Bangladesh user profile and a device session. Requires full name, email, `+880` mobile number, strong password, date of birth, address, and district.
- `POST /api/v1/auth/login` — accepts email or mobile plus password and optional device metadata.
- `POST /api/v1/auth/refresh` — rotates the refresh token. Reuse of an older token revokes its complete token family.
- `POST /api/v1/auth/logout` — revokes the bearer token's current session.
- `POST /api/v1/auth/logout-all` — revokes all active sessions for the authenticated user.
- `GET /api/v1/auth/sessions` — lists the authenticated user's active sessions without token hashes or device fingerprints.
- `DELETE /api/v1/auth/sessions/:sessionId` — revokes one session owned by the authenticated user.

Access tokens are bearer JWTs and default to 15 minutes. Refresh tokens default to 30 days, rotate on every successful refresh, and are stored only as Argon2id hashes. Authentication errors use stable codes including `AUTH_INVALID_CREDENTIALS`, `AUTH_SESSION_EXPIRED`, `AUTH_ACCOUNT_EXISTS`, and `ACCOUNT_SUSPENDED`.

The broader surface above is the target contract; endpoints are added milestone-by-milestone and are not advertised as implemented until tested.
