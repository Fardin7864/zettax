# Community safety rollout and operating requirements

Prepared locally on 28 October 2026. The owner subsequently authorized store
review/production submission, but the suspended listing and signing-key blockers
remain. No deployment occurred. The sequence below records the operational work
required before a future release; it does not certify policy approval.

## Prepared implementation

- A versioned community-rules dialog must be explicitly accepted before creating
  posts or comments. The API also enforces acceptance; hiding the dialog cannot
  bypass it. Restricted accounts cannot restore posting by re-accepting rules.
- Post/comment menus report content, report its author or block its author.
  Reports are persistent and deduplicated by reporter and target. Blocking
  filters posts/comments in both directions and prevents direct post interactions.
  Users can manage their own block list and unblock an account.
- The admin Community area lists open reports, reasons, target text and a link
  to a reported post's image when present. Reviewers can hide content/accounts or
  dismiss reports. Actions write an audit record. Hiding an account restricts
  further posting and hides its existing posts/comments.
- The public socket carries only record IDs and aggregate counts. New/hidden
  content is obtained through the authenticated filtered APIs. Moderation clears
  cached lists before reload; hidden post images are unavailable and not cached.

## Deployment sequence for a future authorized release

1. Back up the database and apply `20261028120000_community_safety` using the
   normal migration runner against the dedicated application schema. A complete
   fresh local database migration/seed/test cycle was verified during preparation.
2. Deploy the API and admin together before distributing the new mobile build.
   Posting requires the new rules endpoints; an app-only update is insufficient.
3. Assign `community.moderate` to designated staff via the existing controlled
   role-change process. The migration creates this permission but grants it to
   no role. Reviewers must also complete recent admin identity verification.
4. Test with two non-production accounts: cancel/accept the rules, report a post,
   comment and user, block/unblock in both directions, review an image, hide and
   dismiss reports, and verify hidden content stays hidden across sockets/reloads.
5. Verify the admin queue is staffed and support is monitored before enabling
   public content. Establish response targets, urgent escalation, review coverage,
   and an appeal/removal process. UI controls alone do not perform moderation.

Keep financial release gates unchanged. This migration does not enable real-money
trading, transfers or predictions, and must not be treated as financial approval.

## API surface

All `/community` routes below require an ordinary access token except the public
rules endpoint. `/admin/community` requires an admin token, explicit moderation
permission and recent identity verification.

| Method/path (under `/api/v1`)               | Purpose                                   |
| ------------------------------------------- | ----------------------------------------- |
| GET `/community/rules`                      | Public current rules                      |
| GET `/community/rules/status`               | Current rules and this user's acceptance  |
| POST `/community/rules/accept`              | Accept exact current `version`            |
| POST `/community/reports`                   | Report `targetType`, `targetId`, `reason` |
| POST `/community/reports/author`            | Report the author of a post/comment       |
| GET/POST `/community/blocks`                | List own blocks / block a target's author |
| DELETE `/community/blocks/:userId`          | Remove only the requesting user's block   |
| GET `/admin/community/reports`              | Oldest 100 unresolved reports             |
| POST `/admin/community/reports/:id/resolve` | `action`: `HIDE` or `DISMISS`             |

Reports accept POST, COMMENT or USER targets, UUID IDs and nonempty reasons up to
1,000 characters. Resolve reports in the queue to access the next oldest batch.
Moderation is idempotent for resolved reports. Restore/escalation decisions require
an operator process; there is no public endpoint to undo a moderator restriction.

## Storage compatibility and remaining verification

The AWS S3 SDK replaces the MinIO Node dependency. Existing `MINIO_*` variable
names and private-bucket encryption remain. Production S3-compatible endpoints
must use TLS (`MINIO_SSL=true`) with the correct port and valid credentials.
Plain HTTP is allowed only for known local hosts outside production. Supabase
storage adapters are unchanged. Test real storage and ClamAV before rollout;
their three integration tests were not run during this preparation.

## Support and account deletion

The owner confirmed `fardinhasan18@gmail.com` as the monitored destination.
Web/mobile deletion pages and privacy contact now use it. Staff must verify
ownership without requesting passwords/PINs, complete deletion/anonymization,
handle linked processors and explain any legally retained records. A request is
not an immediate completed deletion. Test email delivery and the complete manual
workflow before release; these were not verified by sending real messages.

Policy references: [Google UGC policy](https://support.google.com/googleplay/android-developer/answer/9876937)
and [account deletion requirements](https://support.google.com/googleplay/android-developer/answer/10144311).
