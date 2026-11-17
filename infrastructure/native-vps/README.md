# Zettax native VPS operations

The Hostinger Ubuntu VPS at `187.126.114.59` runs without Docker. SSH from the
developer workstation with `ssh root@zettax-vps`. The deployment user is
`zettax`; the active release is `/srv/zettax/current`, a symlink to a directory
under `/srv/zettax/releases/`.

## Services

- `zettax-api.service`: NestJS API on `127.0.0.1:3000`.
- `zettax-admin.service`: Next.js operations console on `127.0.0.1:3001`.
- `zettax-web.service`: Next.js public site on `127.0.0.1:3002`.
- `zettax-worker.service`: financial settlement and outbox worker.
- Nginx serves `zettax.app`, `api.zettax.app`, `admin.zettax.app`, and
  `status.zettax.app` over HTTPS. The apex proxies to the Next.js public site,
  proxies `/api/v1/` and `/socket.io/` to the same API,
  and retains the Android downloads and update manifest;
  the status host exposes the API process health response.
- Certbot renews the shared certificate. Its deploy hook reloads Nginx.

`/srv/zettax/shared/production.env` and `/srv/zettax/secrets/evidence.key`
are readable only by root and the `zettax` group. They are not part of a release.
The environment connects to Supabase project `zxmyfsyndpvxhhtgicbf` using a
restricted PostgreSQL login and private Supabase object storage. The previous
configuration is kept as a root-only rollback file on the VPS. Keep the 32-byte evidence key backed up: old
screenshots cannot be decrypted without it.

## Health checks

```sh
systemctl is-active zettax-api zettax-admin zettax-web zettax-worker nginx certbot.timer
curl -fsS https://api.zettax.app/health
curl -fsS https://api.zettax.app/ready
curl -fsS https://status.zettax.app/
certbot renew --dry-run
```

The public API rejects unauthenticated account requests with HTTP 401.
The admin page loads over HTTPS at `https://admin.zettax.app/`. The public site
and its `/markets`, `/demo`, `/privacy.html`, and `/account-deletion.html` routes
are served by the separate Next.js process.

## Updating the app

Create a new release directory under `/srv/zettax/releases/`, upload the
server source without `node_modules`, `.next`, or local environment files, and
install dependencies with the lockfile using Node 22 and pnpm 9. Build with
`NEXT_PUBLIC_API_URL=https://api.zettax.app/api/v1`. Generate the Prisma client
and check migration status against the configured Supabase database before
switching the `/srv/zettax/current` symlink. Install and enable the checked-in
`zettax-web.service`, replace the Nginx site, run `nginx -t`, and restart the
four Zettax services,
then verify the public health, admin, and market endpoints. Keep the previous
release directory for rollback.

The checked-in files in this directory are the systemd units, Nginx sites,
landing page, certificate reload hook, and first-run environment preparation
script used on the host. Changes to these files require copying and installing
them on the VPS; changing the local copy alone does not update the server.

## Web-only release (1 November 2026)

The public website now has its own release pointer, `/srv/zettax/web-current`,
currently targeting `/srv/zettax/web-releases/20261102-original-ui`. A systemd
scope override at `/etc/systemd/system/zettax-web.service.d/20-web-release.conf`
sets the web working directory and Node command to that pointer. The existing
`/srv/zettax/current` pointer still serves the API, admin and worker; switching
that application pointer alone no longer updates the public website.

For web updates, upload only the public web workspace and its dependency
lockfiles into a new web release directory, install with the frozen lockfile,
and build as `zettax`. Test a transient loopback instance before updating
`web-current` and restarting only `zettax-web`. Preserve the shared production
environment file. Verify the public landing, markets, demo, privacy, deletion,
market API proxy and hashed CSS assets after activation.

The first web-only activation retained the previous service configuration at
`/root/zettax-web-before-20261101/`. To roll back this first activation, remove
only the `20-web-release.conf` override, run `systemctl daemon-reload`, and
restart `zettax-web`; the original unit still targets the previous application
release. Future web releases should retain their previous `web-current` target
for pointer rollback.

## Temporary maintenance (18 October 2026)

The site was placed behind a temporary HTTP 503 maintenance page on 18 October
2026. The exact pre-maintenance Nginx config and service enablement remain on
the VPS at `/root/zettax-maintenance-20261018/` for rollback or a future
maintenance window. The site was restored on 19 October 2026 after local and
public health checks passed. The checked-in `zettax-maintenance-https.conf` and
`maintenance.html` are retained for the next scheduled pause.

For another maintenance window, install the maintenance Nginx config, run
`nginx -t`, reload Nginx, and stop and disable `zettax-api`, `zettax-admin`,
`zettax-web`, and `zettax-worker`. To reactivate, restore the saved production
config first, start and enable those four services, check the local API health
and readiness endpoints, reload Nginx, then verify the public HTTPS endpoints.

## Android releases

Current builds use `com.zettax.app` and install separately from legacy
`com.primevest.app` builds. Android requires the same package name and signing
certificate for an in-place update. The direct flavor uses the workstation
Android debug key. The 1 November
2026 Mac builds have SHA-1 `49:85:D2:69:89:F5:01:AF:8D:84:9A:B3:9A:4B:CF:06:C4:2B:A8:43`,
which differs from the older direct release certificate. Android cannot update
a differently signed installed copy in place; preserve the exact signing key
for subsequent builds. Its Android OAuth client was registered on 1 November
2026 in project `primevest-508313`. The key is not committed. Back it up
securely; loss of the key would require users to reinstall. A dedicated
production key should be introduced only with a planned migration.

For each app release, bump `apps/mobile/pubspec.yaml` version and version code,
commit and push the source, then run
`infrastructure/scripts/publish-mobile-release.ps1 -VersionName X.Y.Z -VersionCode N`.
The script builds the APK, creates a GitHub Release asset, and atomically updates
the hosted APK and `https://zettax.app/updates/latest.json`. The manifest is retained for legacy installations. Starting with 0.2.9 (12),
the app contains no custom APK updater or installer; Google Play installations
receive updates through Google Play. The APK publication script is for the
legacy direct distribution channel and must never upload an artifact to Play.
