# Zettax public website

This is the public Next.js website at `zettax.app`. The Flutter project under
`apps/mobile` remains the Android app; its `web` directory is Flutter platform
scaffolding and is no longer the public website deployment target.

```sh
pnpm install --frozen-lockfile
pnpm --filter @primevest/web dev
```

Open `http://localhost:3002`. The public landing, markets overview, browser
virtual demo, privacy policy, and account deletion page use the Zettax market
API at `https://api.zettax.app/api/v1` for display candles. Set
`MARKET_API_BASE_URL` to another base URL when needed. Crypto depth and recent
trades use Binance public spot endpoints. Market data is display-only and can
be unavailable when a provider is offline or lacks a display license. The
browser demo starts every local browser with $100,000 in virtual cash and saves
virtual orders and holdings only to local storage. Crypto prices stream from
Binance public mini-tickers, and the selected demo chart uses the app's public
market WebSocket with REST refresh as a fallback. The chart supports dragging,
touch pinch zoom, and zoom buttons; wheel scrolling follows the page. The buy
form accepts either a base asset quantity or a virtual USDT spending amount. It does
not connect to the server account or execute financial transactions. The app
links open the Google Play internal testing page.

For production, build `@primevest/web`, install and enable
`infrastructure/native-vps/zettax-web.service`, and apply the matching Nginx
configuration. The public service listens on `127.0.0.1:3002`; Nginx retains
the existing API, socket, download, and update paths.
