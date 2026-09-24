# Zettax Google Play release checklist

The Play Console publisher is the Kodzie organisation account. The Android
package is `com.primevest.app`; the display name is Zettax. Do not create a
second package for routine updates, because package names are immutable on Play.

## Build and signing

1. On the designated Windows release machine, run
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

The website APK is a different release channel and retains the original debug
certificate for compatibility with existing installations. It must **never** be
uploaded to Google Play. Play builds bypass the website APK updater and rely on
Google Play's update mechanism. A website-installed copy may not update in
place to a Play-signed installation because the signing certificates differ.

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
