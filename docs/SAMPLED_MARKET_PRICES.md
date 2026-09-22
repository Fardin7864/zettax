# Price-only market snapshots

The seven stock, index and metal symbols can use Twelve Data's `/price` endpoint. Crypto remains on Binance and is never fetched or stored by this collector. Set `TWELVE_DATA_API_KEY` on the backend and set `TWELVE_DATA_EXTERNAL_DISPLAY_APPROVED=true` only after your Twelve Data agreement permits displaying these symbols to your users **and retaining samples for 30 days**. A free individual/developer key is not sufficient for a public commercial platform.

The backend samples each symbol at most once per 15-minute UTC bucket (up to 672 requests/day for seven symbols), stores the returned value and sample time in `sampled_prices`, and deletes rows older than 30 days on startup and every minute. Responses read only rows newer than 30 days, even if cleanup is delayed. `/price` does not provide an exchange timestamp, so the time shown is the server's sample time and the UI labels the data **Sampled**, not live. Chart bars summarize saved price samples, not genuine exchange OHLC bars; trading execution prices remain separate.

Without configured credentials and rights, the prior explicitly simulated sandbox charts remain in use. Unsupported symbols or an unlicensed provider are never represented as real prices. Keep the API key in server-only environment configuration, not the mobile app.
