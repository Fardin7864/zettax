# Zettax native VPS operations

The Hostinger Ubuntu VPS at `187.126.114.59` runs without Docker. SSH from the
developer workstation with `ssh root@zettax-vps`. The deployment user is
`zettax`; the active release is `/srv/zettax/current`, a symlink to a directory
under `/srv/zettax/releases/`.

## Services

- `zettax-api.service`: NestJS API on `127.0.0.1:3000`.
- `zettax-admin.service`: Next.js operations console on `127.0.0.1:3001`.
- `zettax-worker.service`: financial settlement and outbox worker.
- Nginx serves `zettax.app`, `api.zettax.app`, `admin.zettax.app`, and
  `status.zettax.app` over HTTPS. The apex serves a small public landing page;
  the status host exposes the API process health response.
- Certbot renews the shared certificate. Its deploy hook reloads Nginx.

`/srv/zettax/shared/production.env` and `/srv/zettax/secrets/evidence.key`
are readable only by root and the `zettax` group. They are not part of a release.
The environment connects to the existing Supabase PostgreSQL database and
Supabase S3 screenshot storage. Keep the 32-byte evidence key backed up: old
screenshots cannot be decrypted without it.

## Health checks

```sh
systemctl is-active zettax-api zettax-admin zettax-worker nginx certbot.timer
curl -fsS https://api.zettax.app/health
curl -fsS https://api.zettax.app/ready
curl -fsS https://status.zettax.app/
certbot renew --dry-run
```

The public API rejects unauthenticated account requests with HTTP 401.
The admin page loads over HTTPS at `https://admin.zettax.app/`.

## Updating the app

Create a new release directory under `/srv/zettax/releases/`, upload the
server source without `node_modules`, `.next`, or local environment files, and
install dependencies with the lockfile using Node 22 and pnpm 9. Build with
`NEXT_PUBLIC_API_URL=https://api.zettax.app/api/v1`. Generate the Prisma client
and check migration status against the configured Supabase database before
switching the `/srv/zettax/current` symlink. Restart the three Zettax services,
then verify the public health, admin, and market endpoints. Keep the previous
release directory for rollback.

The checked-in files in this directory are the systemd units, Nginx sites,
landing page, certificate reload hook, and first-run environment preparation
script used on the host. Changes to these files require copying and installing
them on the VPS; changing the local copy alone does not update the server.

## Android releases

Keep `com.primevest.app` and the existing local Android signing key unchanged:
Android requires the same package name and signing certificate for an in-place
update. The current release is signed with the original local debug key for
compatibility with installed copies. The key is not committed. Back it up
securely; loss of the key would require users to reinstall. A dedicated
production key should be introduced only with a planned migration.

For each app release, bump `apps/mobile/pubspec.yaml` version and version code,
commit and push the source, then run
`infrastructure/scripts/publish-mobile-release.ps1 -VersionName X.Y.Z -VersionCode N`.
The script builds the APK, creates a GitHub Release asset, and atomically updates
the hosted APK and `https://zettax.app/updates/latest.json`. The app checks this
manifest on launch/resume, downloads and verifies the APK in-app, then invokes
the Android system installer. Android still requires the user's install approval
and may require one-time "install unknown apps" permission for Zettax.
