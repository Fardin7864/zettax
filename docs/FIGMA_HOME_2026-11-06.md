# Mobile Home refresh — 6 November 2026

Reference: https://www.figma.com/make/Spet5z4aeYl33eTthA3c0s/Crypto-Trading-App-Development?code-node-id=0-6

Scope confirmed by the user: mobile Home only. The public website and other mobile screens retain their presentation. The existing warm dark and yellow theme is retained.

Implemented the reference's compact header, balance panel, dismissible setup guide, Fear & Greed gauge, P2P section, popular-market mini charts and community preview. The compact Home bottom bar preserves Home / Markets / Trade / Portfolio / Profile destinations. Account mode remains available through the header profile control.

Data and behavior:
- Balances use the existing authenticated wallet or guest demo balance, never the design's sample balance.
- Market charts subscribe through the existing live candle provider. Missing/synthetic observations do not become fabricated prices. Percentages describe the loaded minute-candle window rather than a 24-hour return.
- Bitcoin Fear & Greed uses daily public data from Alternative.me, with adjacent attribution. Invalid/stale data shows unavailable. Historical comparisons use actual dates. The public data client receives no account credentials.
- P2P has no offer API, so its section explicitly shows unavailable offers and an explanatory sheet. No fake offers, prices or trade counts.
- Community uses authenticated Zettax posts and actual reactions, realtime invalidation and polling fallback. Report/block controls remain. Clearing rejects older in-flight results. Guests receive a sign-in prompt.
- Help, notifications, profile, mode, funding, markets and community connect to existing flows. No backend deployment or new financial product.

Manrope and DM Sans are from google/fonts, under the bundled SIL Open Font Licenses in apps/mobile/assets/fonts/.

Validation: static analysis; responsive tests at 320/360/402px and 1x/2x text; guide/help/P2P actions; sentiment validation; community reaction and stale-request tests; regression suite. Evidence: artifacts/figma-home-20261106/.

Delivery: APK 0.2.12 (15), installed and opened on OPPO CPH2801 over wireless ADB. All 86 tests pass and static analysis reports no issues. Artifact checks confirm current compiled Dart libraries, retained safety fixes, removed updater and the existing direct-build signature. Live market updates and final responsive layout were observed on the device. SHA-256: c9088eab7c14493db51cc7fbac9188b81378561032bc39f981dad5cb019bde0f.
