$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
function Read-EnvironmentFile([string]$path) {
  $values = @{}
  foreach ($line in Get-Content -LiteralPath $path) {
    if ($line -match '^([A-Z0-9_]+)=(.*)$') { $values[$matches[1]] = $matches[2] }
  }
  return $values
}
$old = Read-EnvironmentFile (Join-Path $root 'infrastructure\secrets\old-local.env')
$oldStorage = Read-EnvironmentFile (Join-Path $root 'infrastructure\secrets\vps-production.env')
$new = Read-EnvironmentFile (Join-Path $root '.env.new-supabase')
if (-not $oldStorage.SUPABASE_S3_ENDPOINT -or -not $oldStorage.SUPABASE_S3_ACCESS_KEY_ID -or
    -not $oldStorage.SUPABASE_S3_SECRET_ACCESS_KEY -or -not $new.SUPABASE_URL -or
    -not $new.SUPABASE_SERVICE_ROLE_KEY) {
  throw 'Old S3 access and the new Supabase service key are required.'
}
$oldBucket = $oldStorage.SUPABASE_EVIDENCE_BUCKET
$newBucket = $new.SUPABASE_EVIDENCE_BUCKET
$oldDb = $old.DATABASE_URL.Split('?')[0] + '?sslmode=require'
$newClient = [System.Net.Http.HttpClient]::new()
try {
  $newClient.DefaultRequestHeaders.Add('apikey', $new.SUPABASE_SERVICE_ROLE_KEY)
  $newClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $new.SUPABASE_SERVICE_ROLE_KEY)
  $bucketBody = [System.Net.Http.StringContent]::new((@{
    id = $newBucket; name = $newBucket; public = $false
    file_size_limit = 5242912; allowed_mime_types = @('application/octet-stream')
  } | ConvertTo-Json -Compress), [System.Text.Encoding]::UTF8, 'application/json')
  $bucketUri = "$($new.SUPABASE_URL)/storage/v1/bucket/$([uri]::EscapeDataString($newBucket))"
  $bucketCheck = $newClient.GetAsync($bucketUri).GetAwaiter().GetResult()
  if ([int]$bucketCheck.StatusCode -eq 404) {
    $bucketResponse = $newClient.PostAsync("$($new.SUPABASE_URL)/storage/v1/bucket", $bucketBody).GetAwaiter().GetResult()
    if (-not $bucketResponse.IsSuccessStatusCode) {
      $message = $bucketResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      throw "Could not create private evidence bucket: $([int]$bucketResponse.StatusCode) $message"
    }
  } elseif (-not $bucketCheck.IsSuccessStatusCode) {
    $message = $bucketCheck.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    throw "Could not verify private evidence bucket: $([int]$bucketCheck.StatusCode) $message"
  }
  $keys = @(psql $oldDb -Atc "SELECT object_key FROM primevest.evidence_files WHERE status <> 'DELETED' ORDER BY object_key")
  if ($LASTEXITCODE -ne 0) { throw 'Could not list source evidence objects.' }
  $copied = 0
  foreach ($key in $keys) {
    if ([string]::IsNullOrWhiteSpace($key)) { continue }
    $encoded = ($key.Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $sourceUri = "$($oldStorage.SUPABASE_S3_ENDPOINT)/$([uri]::EscapeDataString($oldBucket))/$encoded"
    $targetUri = "$($new.SUPABASE_URL)/storage/v1/object/$([uri]::EscapeDataString($newBucket))/$encoded"
    $temporaryObject = [System.IO.Path]::GetTempFileName()
    try {
      curl.exe --silent --show-error --fail --aws-sigv4 "aws:amz:$($oldStorage.SUPABASE_S3_REGION):s3" --user "$($oldStorage.SUPABASE_S3_ACCESS_KEY_ID):$($oldStorage.SUPABASE_S3_SECRET_ACCESS_KEY)" --output $temporaryObject $sourceUri
      if ($LASTEXITCODE -ne 0) { throw 'Source evidence retrieval failed.' }
      $bytes = [System.IO.File]::ReadAllBytes($temporaryObject)
    } finally {
      Remove-Item -LiteralPath $temporaryObject -Force
    }
    $existing = $newClient.GetAsync($targetUri).GetAwaiter().GetResult()
    if ($existing.IsSuccessStatusCode) {
      $existingBytes = $existing.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
      if ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([byte[]]$bytes)) -ne
          [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([byte[]]$existingBytes))) {
        throw 'Target evidence exists with different bytes; refusing to overwrite.'
      }
      continue
    }
    $message = $existing.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ([int]$existing.StatusCode -ne 404 -and $message -notmatch '"code":"NoSuchKey"') {
      throw "Target evidence lookup failed: $([int]$existing.StatusCode) $message"
    }
    $payload = [System.Net.Http.ByteArrayContent]::new([byte[]]$bytes)
    $payload.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/octet-stream')
    $response = $newClient.PostAsync($targetUri, $payload).GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) { throw "Target evidence upload failed: $([int]$response.StatusCode)" }
    $copied++
  }
  Write-Host "Verified $($keys.Count) evidence objects; copied $copied to the new private bucket."
} finally {
  $newClient.Dispose()
}
