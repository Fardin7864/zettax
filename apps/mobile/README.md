# Zettax Mobile

Flutter client for Zettax. Guest demo trading uses virtual funds; signed-in
accounts use the Zettax backend for balances, requests and trading records.
Charts request display-only market data from the backend. Display prices are
not client-supplied execution prices.

## Capabilities

- Official Zettax wordmark, compact mark, native splash, and adaptive icon
- Guest demo with $1,000.00 in virtual funds
- Backend registration, login, Google sign-in and password-reset experiences
- Crypto, forex, stock, index and commodity search, favorites and charts
- Backend-proxied external display candles with provider, freshness, timeframe,
  receipt age, and simulated-fallback labels
- Interactive chart periods from 1 minute to 5 years with live updates
- Guest demo and signed-in account trade flows, moving P/L, settlement and history
- Deposit and withdrawal requests for authenticated accounts, subject to review
- Withdrawal codes from an authenticator app or configured email delivery
- Community posts, image uploads, reactions, comments and replies, shares,
  and live counts
- User-created and Zettax-created crypto price prediction questions with
  Yes/No demo pools, positions, results, and live question updates
- Real-money prediction controls shown in the app but unavailable until the
  backend release controls approve them
- Virtual market-direction predictions with live price charts and history
- Explicit virtual-balance and market-data disclosures

## Verify and build

```powershell
flutter pub get
flutter gen-l10n
dart format lib test
flutter analyze
flutter test
flutter build apk --release --flavor direct
```

The package ID is `com.primevest.app`. Android has separate `direct` and `play`
distribution flavors. The direct APK keeps its historical certificate so existing
website-installed copies can update in place; the Play App Bundle uses a private
upload key and Play App Signing. Those two distribution channels do not share a
device-installation certificate, so a website-installed copy may need to be
uninstalled before its first Play installation (after backing up any local-only
demo data). The Play build excludes the APK installer and lets Google Play
deliver updates.

Build the direct APK with `flutter build apk --release --flavor direct`. Build
the Play App Bundle with `infrastructure/scripts/build-play-bundle.ps1` from
the repository root. On the designated release machine, run it once with
`-CreateUploadKey` to generate the private upload key. Keep the key and its
DPAPI-protected password backup together; the password file can only be
decrypted by the same Windows account on the same machine. Never commit either
file. See [Play release checklist](../../docs/PLAY_RELEASE.md).

## Market-data backend

Android emulators use `http://10.0.2.2:3000/api/v1` by default. For a physical
Android device connected over USB, reverse the backend port and build with the
loopback URL:

```powershell
adb reverse tcp:3000 tcp:3000
flutter run --flavor direct --dart-define=PRIMEVEST_API_BASE_URL=http://127.0.0.1:3000/api/v1
```

Use an HTTPS endpoint for any deployed environment:

```powershell
flutter build apk --release --flavor direct --dart-define=PRIMEVEST_API_BASE_URL=https://api.zettax.app/api/v1
```

Android cleartext networking is denied by default. The checked-in network
security policy permits only emulator/loopback hosts for local development.
