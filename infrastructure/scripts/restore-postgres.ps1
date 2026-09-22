param(
  [Parameter(Mandatory = $true)][string]$BackupFile,
  [string[]]$ComposeFiles = @("docker-compose.yml"),
  [string]$EnvFile = "",
  [string]$ComposeProject = "primevest",
  [string]$DatabaseService = "postgres",
  [string]$DatabaseUser = "primevest",
  [string]$SourceDatabase = "primevest",
  [string]$TargetDatabase = "primevest_restore_verification"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

foreach ($value in @(
    $ComposeProject,
    $DatabaseService,
    $DatabaseUser,
    $SourceDatabase,
    $TargetDatabase
  )) {
  if ($value -notmatch "^[A-Za-z_][A-Za-z0-9_-]*$") {
    throw "Unsafe project, service, user, or database identifier: $value"
  }
}
if ($TargetDatabase -eq $SourceDatabase) {
  throw "TargetDatabase must never be the source database."
}

$resolvedBackup = (Resolve-Path -LiteralPath $BackupFile).Path
$checksumFile = "$resolvedBackup.sha256"
if (-not (Test-Path -LiteralPath $checksumFile)) {
  throw "Checksum sidecar is required: $checksumFile"
}
$expectedChecksum = ((Get-Content -LiteralPath $checksumFile -Raw).Trim() -split "\s+")[0]
$actualChecksum = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedBackup).Hash
if ($expectedChecksum -ne $actualChecksum) {
  throw "Backup SHA-256 checksum verification failed."
}

$composeArguments = @("compose")
if ($EnvFile) {
  $composeArguments += @("--env-file", (Resolve-Path -LiteralPath $EnvFile).Path)
}
foreach ($file in $ComposeFiles) {
  $composeArguments += @("-f", (Resolve-Path -LiteralPath $file).Path)
}
$composeArguments += @("-p", $ComposeProject)

$containerId = ([string](& docker @composeArguments ps -q $DatabaseService)).Trim()
if ($LASTEXITCODE -ne 0 -or -not $containerId -or $containerId -match "\s") {
  throw "Expected exactly one running $DatabaseService container."
}

$databaseExistsOutput = & docker @composeArguments exec -T $DatabaseService psql `
    --username $DatabaseUser `
    --dbname postgres `
    --tuples-only `
    --no-align `
    --command "SELECT 1 FROM pg_database WHERE datname = '$TargetDatabase';"
if ($LASTEXITCODE -ne 0) { throw "Could not inspect target database state." }
$databaseExists = if ($null -eq $databaseExistsOutput) {
  ""
} else {
  ([string]$databaseExistsOutput).Trim()
}
if ($databaseExists -eq "1") {
  throw "Target database already exists. Choose a new verification database."
}

$containerTemp = "/tmp/primevest-restore-$([guid]::NewGuid().ToString('N')).dump"
try {
  & docker cp $resolvedBackup "${containerId}:$containerTemp"
  if ($LASTEXITCODE -ne 0) { throw "docker cp failed." }

  & docker @composeArguments exec -T $DatabaseService createdb `
    --username $DatabaseUser $TargetDatabase
  if ($LASTEXITCODE -ne 0) { throw "Could not create verification database." }

  & docker @composeArguments exec -T $DatabaseService pg_restore `
    --username $DatabaseUser `
    --dbname $TargetDatabase `
    --exit-on-error `
    --no-owner `
    --no-privileges `
    $containerTemp
  if ($LASTEXITCODE -ne 0) {
    throw "Restore failed. The verification database is retained for investigation."
  }
}
finally {
  & docker @composeArguments exec -T $DatabaseService rm -f -- $containerTemp 2>$null
}

$verificationSql = @"
SELECT 'public_tables=' || COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';
SELECT 'failed_migrations=' || COUNT(*) FROM _prisma_migrations WHERE finished_at IS NULL OR rolled_back_at IS NOT NULL;
SELECT 'unbalanced_ledger_transactions=' || COUNT(*)
FROM (
  SELECT transaction_id
  FROM ledger_entries
  GROUP BY transaction_id
  HAVING SUM(CASE direction WHEN 'DEBIT' THEN amount ELSE -amount END) <> 0
) AS unbalanced;
"@

& docker @composeArguments exec -T $DatabaseService psql `
  --username $DatabaseUser `
  --dbname $TargetDatabase `
  --no-align `
  --tuples-only `
  --set ON_ERROR_STOP=1 `
  --command $verificationSql
if ($LASTEXITCODE -ne 0) { throw "Post-restore verification queries failed." }

Write-Output "Restore verification database retained as $TargetDatabase for inspection."
