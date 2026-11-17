# Zettax Google Play release checklist

**Superseding account-level status:** Google terminated kodzie on 28 October
2026 for Related Account Violation. An account-level appeal was submitted and
confirmed at **22:32 Asia/Dhaka**. Publishing remains blocked; a new package,
app deletion or upload-key reset does not restore eligibility. See
[the account appeal record](PLAY_ACCOUNT_TERMINATION_STATUS_2026-10-28.md).
The earlier app-level preparation and recovery notes below are historical.

**Current state (28 October 2026):** the owner authorized production/review
submission in a follow-up. Publication is blocked by the suspension, unavailable
release actions and missing original upload key. A technical reconsideration
request was sent to Google Play support in the existing case at 17:27 Asia/Dhaka,
followed by verified build-integrity evidence at 17:33;
no bundle was uploaded and no production rollout occurred.
The appeal was rejected for phishing. See
[the current investigation](ANDROID_SECURITY_REVIEW_2026-10-28.md) and
[community safety rollout requirements](COMMUNITY_SAFETY_OPERATIONS.md).
Historical routine-update instructions below do not override Google's specific
new-app recovery instructions or the unresolved release blockers.

The owner authorized upload-key recovery later on 28 October. A replacement key
and public certificate are prepared locally. The owner submitted the signing-key
support request, and Google confirmed receipt with status **Pending / Case ID
pending** and an email response within 2 working days (some tickets take longer).
**No reset approval or activation is confirmed.** See
[the recovery record](PLAY_UPLOAD_KEY_RECOVERY_2026-10-28.md).

The legacy Zettax listing in the Kodzie organisation account uses
`com.primevest.app`. Current Android builds use `com.zettax.app` and require a
separate Play listing because package names are immutable on Play.

## Build and signing

1. On the designated Windows release machine (with Python 3 installed), run
   `infrastructure/scripts/build-play-bundle.ps1`. The first run requires
   `-CreateUploadKey`; never run that switch again after a key exists.
2. Upload `apps/mobile/build/app/outputs/bundle/playRelease/app-play-release.aab`.
   Increase the `pubspec.yaml` build number for every new upload.
3. Back up both ignored files under `infrastructure/secrets/`:
   `zettax-play-upload.jks` and `zettax-play-upload-password.dpapi`.
   The password file is encrypted for the current Windows account and machine;
   arrange a separate secure, offline recovery copy of the password before
   decommissioning this machine. The upload key is not the Play app signing key.
4. After the first upload, copy the **Play app signing certificate** SHA-1 and
   SHA-256 from Play Console into the Android OAuth client configuration in
   Google Cloud. The local upload certificate is not the identity seen on
   users' Play-installed devices.
5. Verify the merged Play manifest has target SDK 36 and no
   `REQUEST_INSTALL_PACKAGES` permission. Check the AAB signature and run the
   mobile analysis/tests. Test on a 16 KB page-size Android emulator.

The website APK is a different release channel and uses the workstation debug
certificate. It must **never** be
uploaded to Google Play. All builds now omit the website APK updater entirely:
there is no update manifest polling, executable download, installer channel,
unknown-source settings intent, or install-packages permission. Play installs
receive updates through Google Play. A website-installed copy may not update in
place to a Play-signed installation because the signing certificates differ.

Release signing is selected by flavor. Play release builds require the existing
upload keystore and password environment variables to produce a signed bundle;
without them, Gradle produces an **unsigned audit artifact**, which must not be
uploaded. The optional `ZETTAX_ANDROID_DISTRIBUTION` variable cannot make a Play
release fall back to the direct/debug signing key. Never generate a replacement
upload key to work around a missing original key.

Run the following on the exact bundle before uploading:

```sh
python3 infrastructure/scripts/verify-play-artifact.py apps/mobile/build/app/outputs/bundle/playRelease/app-play-release.aab --native-libs apps/mobile/build/app/intermediates/flutter/playRelease/jniLibs
```

This checks manifests, DEX and Dart AOT libraries for removed updater markers,
requires the current safety-disclosure text in every packaged Dart library,
rejects embedded APK/JAR files and compares ELF build IDs with the current
compilation for every ABI. Do not omit `--native-libs` for release verification.
It is a regression gate, not a malware scan or a guarantee of policy approval.
The Windows release script runs the same gate automatically.

The installed Flutter 3.44.3 has a confirmed flavored native-library packaging
regression: builds can report success while packaging stale Dart code. The app
Gradle configuration now tracks the generated native-library directory as a task
input. A source-only incremental rebuild was tested without cleaning: every
packaged ABI changed and matched the newly compiled library. See
[Flutter issue 187553](https://github.com/flutter/flutter/issues/187553).
Older bundle fingerprints recorded before this fix do not verify inclusion of
the current fixes. The current verified unsigned bundle SHA-256 is
`f7c222258034afbea63dafaf5cfc30e02a2389516f6e9e3a049f682b65a356ac`.

## Suspension on 26 October 2026

Google identified version code 11 under `MALWARE`. Play Console confirms the
app is suspended; the enforcement email does not identify a malware subtype,
SDK, class, or file. The local source previously relied on a Dart build define
and Android flavor check to hide a shared APK installer. This is a concrete
policy risk, but the original submitted version 11 binary has not been obtained
and Google has not confirmed it as the reason for suspension.

Version 0.2.9 (12) removes that mechanism from every distribution and separates
release signing by flavor. See `docs/PLAY_SUSPENSION_APPEAL.md` for the draft
appeal and verification record. A local code fix does not restore a suspended
listing. Google subsequently rejected the appeal and specified phishing. Its
response, supplied on 28 October, permits a genuinely corrected new app with a
new package and app name if the account is eligible. Do not resubmit version 11
or treat a rename as remediation. Follow that recovery route only after the
phishing finding is investigated and resolved; see the updated review record.

## Play Console setup

- The account owner must verify and attest to Developer Programme Policy and
  export-law compliance when creating the app. Do not click these attestations
  based on a build passing tests.
- Complete the privacy policy, data safety, account deletion, app access,
  financial features, ads, target audience and content-rating declarations
  accurately before closed or open testing. Funding/payout behavior must be
  clarified before selecting financial features or writing public claims.
- Use only actual app screenshots without real user data. Keep store copy
  precise: reference market prices, virtual trading, and no promise of profit.
- Add the supplied testers to internal/closed email lists. Each tester needs
  to opt in through the Play testing link; merely adding an address does not
  install the app or count as participation.
- Start internal testing first, then closed testing. Open testing exposes a
  test version to the public and requires the completed store setup and any
  account-specific Play Console eligibility. Verify each rollout reaches an
  active/published status rather than stopping at a draft release.
- Google reviews submissions and may reject them. No build process can
  guarantee acceptance, especially for finance-related functionality.

## Security preparation on 28 October 2026

See [the security review](ANDROID_SECURITY_REVIEW_2026-10-28.md) for prepared
transport/disclosure fixes, dependency updates, verification evidence and the
remaining release blockers. The owner selected feature preservation and
preparation without publication. Do not treat this bundle as cleared for Play.
