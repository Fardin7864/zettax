param(
  [string[]]$ComposeFiles = @("docker-compose.yml"),
  [string]$EnvFile = "",
  [string]$ComposeProject = "primevest",
  [string]$DatabaseService = "postgres",
  [string]$DatabaseUser = "primevest",
  [string]$DatabaseName = "primevest",
  [string]$Destination = "./backups",
  [ValidateRange(0, 9)][int]$CompressionLevel = 9,
  [ValidateRange(1, 3650)][int]$RetentionDays = 14
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

foreach ($value in @($ComposeProject, $DatabaseService, $DatabaseUser, $DatabaseName)) {
  if ($value -notmatch "^[A-Za-z_][A-Za-z0-9_-]*$") {
    throw "Unsafe project, service, user, or database identifier: $value"
  }
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

$resolvedDestination = [System.IO.Path]::GetFullPath(
  $Destination,
  (Get-Location).Path
)
New-Item -ItemType Directory -Force -Path $resolvedDestination | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$baseName = "primevest-$DatabaseName-$stamp"
$output = Join-Path $resolvedDestination "$baseName.dump"
$checksumFile = "$output.sha256"
$metadataFile = "$output.json"
$containerTemp = "/tmp/$baseName.dump"

try {
  & docker @composeArguments exec -T $DatabaseService pg_dump `
    --username $DatabaseUser `
    --dbname $DatabaseName `
    --format custom `
    --compress $CompressionLevel `
    --no-owner `
    --no-privileges `
    --file $containerTemp
  if ($LASTEXITCODE -ne 0) { throw "pg_dump failed." }

  & docker cp "${containerId}:$containerTemp" $output
  if ($LASTEXITCODE -ne 0) { throw "docker cp failed." }
}
finally {
  & docker @composeArguments exec -T $DatabaseService rm -f -- $containerTemp 2>$null
}

$fileInfo = Get-Item -LiteralPath $output
if ($fileInfo.Length -le 0) { throw "Backup file is empty." }
$checksum = (Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant()
Set-Content -LiteralPath $checksumFile -Encoding ascii -Value "$checksum  $($fileInfo.Name)"

[ordered]@{
  format = "postgres-custom"
  database = $DatabaseName
  createdAt = (Get-Date).ToUniversalTime().ToString("o")
  bytes = $fileInfo.Length
  sha256 = $checksum
  encrypted = $false
} | ConvertTo-Json | Set-Content -LiteralPath $metadataFile -Encoding utf8

$cutoff = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -LiteralPath $resolvedDestination -Filter "primevest-*.dump" -File |
  Where-Object LastWriteTime -lt $cutoff |
  ForEach-Object {
    Remove-Item -Force -LiteralPath $_.FullName
    foreach ($sidecar in @("$($_.FullName).sha256", "$($_.FullName).json")) {
      if (Test-Path -LiteralPath $sidecar) { Remove-Item -Force -LiteralPath $sidecar }
    }
  }

Write-Output $output
Write-Output $checksumFile
Write-Warning "The dump is compressed and checksummed but not encrypted. Encrypt it before off-host storage."
