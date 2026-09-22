# Mobile

The Flutter client uses Riverpod, `go_router`, Dio, secure storage, generated ARB localization, and a PrimeVest-owned dark design system. The Phase 1 shell implements splash, onboarding, easy demo entry, the five-tab navigation, and an explicitly simulated demo overview. Mobile state is a projection only: server configuration, timestamps, fees, prices, balances, and permissions are authoritative.

Asset-detail and primary Trade charts request normalized candles from the PrimeVest backend, never directly from a vendor. The client validates the standard API envelope and OHLC ranges, shows provider, freshness, effective timeframe, receipt age, and any simulated fallback, and refreshes visible series every 15 seconds. External candles are display-only. The demo execution engine continues to use its separate simulated feed, and the UI labels both sources so a chart cannot be mistaken for execution evidence.

Release deployments must pass `PRIMEVEST_API_BASE_URL` as an HTTPS URL. Android denies cleartext by default and permits cleartext only for emulator/loopback development addresses. A USB-connected device can use `adb reverse tcp:3000 tcp:3000` with a loopback API URL.

Platform wrappers are generated with Flutter stable as documented in the README. Production work must add certificate-aware networking, secure token rotation, root/jailbreak risk signals without blanket exclusion, screenshot/privacy controls for sensitive screens, deep-link validation, and store privacy/account-deletion disclosures.
