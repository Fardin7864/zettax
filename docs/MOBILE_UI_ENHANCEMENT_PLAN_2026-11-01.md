# Mobile UI enhancement plan — 1 November 2026

## Goal
Make the existing forest/mint Zettax interface more informative and polished with lightweight graphs and meters. Preserve authentication, funding, trading, community, prediction, account modes, APIs and balances. Keep the in-app updater removed.

## Implementation
1. Shared visual components: native-painted price sparkline, observed market-direction gauge, portfolio allocation ring, and balance usage meter. Every visual has a text equivalent; handle missing, flat, zero and invalid data.
2. Home: live market overview for three crypto markets, with provider candle history, price movement graphs and an explicitly scoped rising/falling gauge. No invented fear/greed or investment advice score.
3. Markets: compact sparklines reuse each row's existing candle subscription. Hide secondary graphics on narrow layouts when space is needed for prices.
4. Portfolio: visualize available versus locked funds from the selected account; loading/unknown amounts stay unavailable. Add a small usage bar on existing balance cards.
5. Validation: meaningful calculations and rendering tests, larger text/narrow screens, Flutter analysis and full suite; direct-release APK build, signature and native packaging/updater audit.

## Delivery
A new APK, screenshots of the changed components and verification record. This task does not deploy the web or change the backend.

## Completed

- Implemented `financial_visuals.dart`: price graphs with area shading, animated direction gauge, allocation ring, and balance meter. Existing market rows and account screens use these components.
- Market direction counts only non-synthetic candle histories with at least two observations; unavailable histories never get fabricated returns. The gauge explicitly describes its three-market sample and loaded 1-minute bars.
- Portfolio totals, available amounts and locked amounts remain visible. The percentage represents available funds divided by available plus locked funds; empty/unknown/invalid balances do not show a misleading 100%.
- Motion respects the operating system's reduced-motion setting. Small-screen tests cover text scales through 2× for allocation and balance meters and 1.6× for market pulse.
- Flutter analysis: no issues. Full mobile suite: 83 passed, including new invalid/zero balance, chart rendering, large-text, and synthetic-data exclusion tests.
- Component rendering preview: `artifacts/ui-enhancement-20261101/visual-components-preview.png`. This preview uses test fixtures for verification; the production widgets consume existing APIs and account data. Temporary screenshot harness removed.
- Release: version 0.2.10 (13), direct Android APK. The in-app updater remains absent. No website/backend deployment or store submission is part of this change.
- Physical Android device not connected; verification used widget rendering, tests and APK inspection.

Final APK SHA-256: `63737abc42d5852994c56a373036163158d8b86683bff417a50b3ab22d9f8737`. Signature verified; packaged native libraries match the current compilation across all ABIs; removed updater markers absent. Desktop copy: `/Users/fardinhasan/Desktop/Zettax-0.2.10-ui-enhanced.apk`.
