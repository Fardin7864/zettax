# Private Supabase screenshot storage

Configure these values in the backend environment (local development uses `.env.local`):

```dotenv
EVIDENCE_STORAGE_PROVIDER=supabase
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVER_ONLY_SERVICE_ROLE_KEY
SUPABASE_EVIDENCE_BUCKET=primevest-evidence
EVIDENCE_ENCRYPTION_KEY_FILE=ABSOLUTE_PATH_TO_EXISTING_32_BYTE_KEY_FILE
```

Never put the service-role key in Flutter, browser code, a `NEXT_PUBLIC_` variable, source control, logs, or chat. A database password is not a Storage API key.

## S3 credentials alternative

Supabase S3 credentials are also supported; they are not service-role keys. Set `EVIDENCE_STORAGE_PROVIDER=supabase-s3`, `SUPABASE_S3_ENDPOINT` to the complete `/storage/v1/s3` endpoint, `SUPABASE_S3_ACCESS_KEY_ID`, `SUPABASE_S3_SECRET_ACCESS_KEY`, and `SUPABASE_S3_REGION`. Keep these secrets server-side in the ignored environment file. `SUPABASE_SERVICE_ROLE_KEY` is not required for S3 mode.

S3 mode uses Signature V4 over HTTPS. Because Supabase does not implement S3 bucket-policy/ACL APIs, the server verifies private access from `storage.buckets` through its existing database connection. Do not remove the server database identity's access to this metadata. New S3 buckets default to private; upload fails if the bucket is public. The file-size and MIME checks remain enforced by the backend.

Run `pnpm exec tsx scripts/verify-supabase-storage.ts` from `apps/backend` to create the configured bucket if needed, verify private access, and perform a temporary object upload/download/delete. It never prints credentials and only deletes its own random verification object.

The server creates `primevest-evidence` if absent, with public access disabled, a 5 MB plus encryption-header size limit, and `application/octet-stream` as the allowed content type. Existing public buckets are rejected. Do not add public/anonymous read policies. Admin previews are authenticated backend requests, not public object links.

Deposit screenshots use image validation, PNG normalization and AES-256-GCM encryption, without an antivirus scanner or Docker. Server credentials and the encryption key are required for attachments. Other evidence purposes retain their existing scanning rules. Deposits without attachments do not require storage.

After setting the environment, restart the backend through `infrastructure/scripts/start-supabase-dev.ps1` so it imports `.env.local`. Verify a screenshot deposit and its authenticated admin preview before enabling uploads for users.

The backend checks for expired DEPOSIT evidence every minute and on startup. At seven days from upload it deletes the actual object via Supabase Storage, then marks its database metadata `DELETED`. Request and accounting history remain intact. Storage errors leave the metadata retryable. Expired screenshots cannot be previewed even if deletion is retrying. Keep the backend running; downtime delays physical deletion until startup. Other evidence purposes are not deleted by this policy.

For existing MinIO deployments, explicitly set `EVIDENCE_STORAGE_PROVIDER=minio` to preserve access to old objects. This change does not migrate existing evidence objects between providers.

Reference: [Supabase private bucket access](https://supabase.com/docs/guides/storage/buckets/fundamentals).
