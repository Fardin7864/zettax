# Zettax Mobile

Flutter client demo for Zettax. The demo trading engine and instrument
catalogue use bundled data through a `MockPrimeVestApi` boundary, so trading
continues without Docker or internet access. When the Zettax backend is
reachable, asset and Trade charts request external display-only candles through
the backend. External data is never passed to the demo execution engine.

## Demo capabilities

- Official Zettax wordmark, compact mark, native splash, and adaptive icon
- Guest demo with ৳100,000.00 in virtual funds
- Mock registration, login, and password-reset experiences
- Five simulated asset classes, search, favorites, and rolling price charts
- Backend-proxied external display candles with provider, freshness, timeframe,
  receipt age, and simulated-fallback labels
- Interactive 1m, 5m, 15m, 30m, 1h, 4h, and 1d chart timeframes with automatic
  and manual refresh
- Normal BUY/SELL and timed UP/DOWN demo trades
- Pre-trade confirmation with price, payout, and zero-fee disclosure
- Moving P/L, closing positions, settlement, history, and full transactions
- Explicit DEMO and simulated-market disclosures throughout

## Verify and build

```powershell
flutter pub get
flutter gen-l10n
dart format lib test
flutter analyze
flutter test
flutter build apk --release
```

The package ID is `com.primevest.app`. The release APK currently uses a
development signature for direct client testing and is not a Play Store build.

## Market-data backend

Android emulators use `http://10.0.2.2:3000/api/v1` by default. For a physical
Android device connected over USB, reverse the backend port and build with the
loopback URL:

```powershell
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=PRIMEVEST_API_BASE_URL=http://127.0.0.1:3000/api/v1
```

Use an HTTPS endpoint for any deployed environment:

```powershell
flutter build apk --release --dart-define=PRIMEVEST_API_BASE_URL=https://api.zettax.app/api/v1
```

Android cleartext networking is denied by default. The checked-in network
security policy permits only emulator/loopback hosts for local development.
