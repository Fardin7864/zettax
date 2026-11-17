# Zettax color refresh — 1 November 2026

Applied the client's reference palette to the existing Flutter mobile application and Next.js web application. Existing routes, layouts, APIs, balances, order calculations and account features are preserved.

Palette: background `#07110F`, surface `#0E1D19`, raised surface `#163128`, border `#203C33`, primary mint `#2BDD9F`, primary text `#E7EEF0`, muted text `#8AA49C`, negative `#FF526F`. Balance cards use a subtle upper-right green glow; workspaces use a dark green gradient. Existing Zettax logos, provider branding and distinct moving-average series colors remain recognizable.

The in-app APK updater was already removed from the working source. This build confirms its absence in both source and packaged code. Android permissions contain Internet, biometric/fingerprint and the generated private receiver permission; no package installation permission is present.

## Deliverables

- Direct-install APK: `artifacts/theme-refresh-20261101/Zettax-forest-mint-2026-11-01.apk`
- Desktop copy: `/Users/fardinhasan/Desktop/Zettax-forest-mint-2026-11-01.apk`
- Existing direct flavor signing retained. This is not a Play submission.
- Version: 0.2.9 (12).
- SHA-256: `1fd67c9e54e60a3b0932fe48e7931a12a68f94285e58ccfa696cf8696d9b9d73`.
- Web deployed on 1 November 2026 to https://zettax.app/ after SSH access was restored. Only the web service was restarted; the API, admin and worker retained their existing processes.

## Validation

- Flutter analysis: no issues.
- Existing mobile suite: 76 tests passed.
- Next.js production build: passed, including lint/type validation.
- APK v2 signing verification: passed.
- Artifact audit: no removed updater markers; current safety markers present; every packaged Dart native build ID matches the fresh direct-release compilation.
- Desktop browser review: landing, markets and demo trading pages. Market prices and live order book loaded from the existing APIs.
- Responsive browser review at 390 × 844: document width equals viewport width, with chart and order controls visible.
- Mobile widget rendering captured for home, markets and portfolio; preview harness used mocked networking and was removed after capture. These are rendering previews, not physical-device tests. No Android device was connected.
- Initial APK attempt ran out of disk space. Removed only generated iOS simulator outputs, generated Android intermediates and an obsolete Gradle transform cache; rebuild passed. Existing signing material, source files and earlier release evidence were preserved.

Build/test logs and browser screenshots are in `artifacts/theme-refresh-20261101/`.

## Production deployment

- Release: `/srv/zettax/web-releases/20261101-forest-mint`.
- Web pointer: `/srv/zettax/web-current`.
- Next build ID: `jiK37qDX1YipINLmQXWKX`.
- Source archive SHA-256: `5e397a29d5c0208a9f1238ba3233c579ba002c30f1dea38c57000c16f52a279e`.
- Fresh frozen dependency install and production build on VPS passed.
- Staged loopback checks passed before activation; preview service stopped after activation.
- Public landing, markets, demo, privacy, account deletion and market proxy returned HTTP 200. Public hashed CSS contains the forest and mint palette. Browser confirmed the live theme without horizontal overflow at its 452px viewport.
- API PID 412161, admin PID 412169 and worker PID 412165 remained unchanged.
- Previous unit retained for rollback in `/root/zettax-web-before-20261101/`.
- Build, staging, activation and public check logs are under `artifacts/theme-refresh-20261101/`.
