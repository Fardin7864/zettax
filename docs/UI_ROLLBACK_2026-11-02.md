# UI rollback — 2 November 2026

Restored the mobile and public web presentation from before the 1 November forest/mint refresh. Removed the new market pulse panel, added sparklines, allocation rings, balance meters and workspace gradients. Existing chart functionality remains.

Only presentation files were restored. Preserved updater removal, transport/security hardening, funding disclosures, community safety, virtual settlement fixes, support contacts and the Google OAuth client registration. The home screen retains its accurate virtual price-move settlement text.

The November UI source is recoverable from `artifacts/ui-rollback-20261102/november-ui-backup.tar.gz`. Removed only the three new UI component/test files introduced with those changes.

Mobile release version 0.2.11 (14) enables installation over the previous direct build using the same current Mac signing certificate. Full remaining suite: 76 tests passed. Flutter analysis: no issues.

Web release: `/srv/zettax/web-releases/20261102-original-ui`, through `/srv/zettax/web-current`. Only the web service is restarted. Prior forest/mint release is retained for recovery. Build, activation and artifact audit logs are in `artifacts/ui-rollback-20261102/`.

Completed: previous web theme verified publicly (`#FCD535` accent, `#030E15` background), all public routes/API proxy passed. API/admin/worker PIDs unchanged. APK signature verified, fresh native build IDs match, updater absent. Desktop APK: `/Users/fardinhasan/Desktop/Zettax-0.2.11-previous-UI.apk`.
