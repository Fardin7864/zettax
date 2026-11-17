# Figma mobile screen refresh — 6 November 2026

Reference: https://www.figma.com/make/Spet5z4aeYl33eTthA3c0s/Crypto-Trading-App-Development?code-node-id=0-6

The user approved the new Home and requested the same presentation across the remaining mobile app, keeping Zettax yellow. The public website and backend are outside this change.

## Implementation

- Shared terminal presentation: warm dark gradient, existing yellow accent, Manrope headings, DM Sans body text, outlined rounded panels, compact tabs and controls. Supporting routes use the same title, form and card styling.
- Markets: reference hero, category tabs, outlined table, live prices, favorites and retained search. Catalogue rendering is lazy. Movement is labelled as the loaded price window, not misrepresented as a 24-hour return.
- Portfolio: total assets summary and horizontal selectors, actual available/locked funds, open positions, timed contracts and closed trade history. Existing close-position calls, fees and settlement details remain available.
- Trade: portfolio summary, searchable instrument list, selected instrument chart, timeframes, order controls and order monitor arranged as the reference's vertical workspace. The existing submission, amount/duration validation, pending-request handling, accounting and settlement code is unchanged. The chart retains OHLC selection, pinch zoom, pan, all three MAs, volume and trade markers. A chart settings panel exposes existing MA values and candlestick/line presentation.
- Navigation: consistent bottom bar on all five mobile destinations, including Trade. URL query and selected tab remain synchronized. Scrolling content stays below the native status area.
- Profile: reference panel treatment around the actual account identity and existing settings/actions. No sample identity or fabricated verification status is shown.
- Community: inline entry panel opens the existing text/image composer. Actual posts and reaction/comment/share counts remain, including dislikes, replies, reporting, blocking, pagination and realtime updates.
- Funding, security, predictions, education, language, account editing and transaction routes share the visual system while retaining their existing fields, safeguards and actions.

## Intentional product differences

The prototype contains simulated sample wallets, verified offers, transfers, perpetual futures and unsupported indicator options. These are not represented as available Zettax products. Existing Positions / Timed contracts / Trade history occupy the reference's portfolio selector layout. Existing trading modes and funding routes are preserved. Home's previously approved unavailable P2P state remains truthful. No account reset, new financial product, server deployment or store submission is performed.

## Verification

- Static analysis and the complete mobile test suite.
- Layout checks at 320px / 360px with normal and doubled text, plus the existing Home checks at 320px / 360px / 402px.
- Search, tab navigation, trading mode switches, chart settings and signed-in community feed/composer indexing.
- Physical OPPO CPH2801 inspection over wireless ADB, with screenshots in artifacts/figma-pages-20261106/.
- APK native build identity, existing direct-build signing certificate, updater removal and retained safety markers are verified before delivery.

The Figma MCP rejected edit access, so the rendered browser preview supplied the design measurements and screenshots. Manrope and DM Sans retain their bundled licenses.

## Delivery

APK 0.2.13 (16) installed and launched on the OPPO over wireless ADB. All 103 mobile tests pass; static analysis reports no issues. Direct-build signing and native build identities pass verification; updater removal and existing safety markers remain intact. Trade business methods match the pre-refresh source after whitespace normalization. No backend or website deployment was performed.

APK: /Users/fardinhasan/Desktop/Zettax-0.2.13-Figma-UI.apk

SHA-256: 04e94ac676a82314ba5f89a12f23317bfea0cd12cc86994fd30236df41d5fae7
