param(
  [string]$EnvFile = ".env.local",
  [switch]$ApplyMigrations
)

$ErrorActionPreference = "Stop"
$workspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location -LiteralPath $workspace

function Import-PrimeVestEnv {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing $Path. Copy infrastructure/env/local-supabase.env.example to .env.local and set DATABASE_URL."
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^\s*$' -or $line -match '^\s*#') {
      continue
    }
    if ($line -notmatch '^\s*([^=]+?)\s*=\s*(.*)\s*$') {
      throw "Invalid environment entry in ${Path}: $line"
    }
    $name = $matches[1]
    $value = $matches[2]
    if (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    ) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    [Environment]::SetEnvironmentVariable($name, $value, "Process")
  }
}

Import-PrimeVestEnv -Path (Join-Path $workspace $EnvFile)

if ([string]::IsNullOrWhiteSpace($env:DATABASE_URL)) {
  throw "DATABASE_URL is required. Use the Supabase PostgreSQL pooler URL."
}

$env:NODE_ENV = "development"
$env:BACKEND_HOST = "0.0.0.0"
$env:BACKEND_PORT = "3000"
$env:CORS_ORIGINS = if ($env:CORS_ORIGINS) { $env:CORS_ORIGINS } else { "http://localhost:3001" }
$env:NEXT_PUBLIC_API_URL = if ($env:NEXT_PUBLIC_API_URL) { $env:NEXT_PUBLIC_API_URL } else { "http://localhost:3000/api/v1" }
$env:HEALTH_REQUIRE_REDIS = if ($env:HEALTH_REQUIRE_REDIS) { $env:HEALTH_REQUIRE_REDIS } else { "false" }
$env:HEALTH_REQUIRE_OBJECT_STORAGE = if ($env:HEALTH_REQUIRE_OBJECT_STORAGE) { $env:HEALTH_REQUIRE_OBJECT_STORAGE } else { "false" }

if ($ApplyMigrations) {
  Write-Host "Applying committed Prisma migrations to the configured database..."
  & pnpm --filter '@primevest/backend' prisma:deploy
  if ($LASTEXITCODE -ne 0) {
    throw "Prisma migration deployment failed."
  }
}

Write-Host "Starting PrimeVest without Docker: API http://localhost:3000, admin http://localhost:3001, settlement worker"
Write-Host "Redis and object-storage readiness checks are disabled locally; evidence upload remains fail-closed unless configured."
& pnpm --filter '@primevest/backend' build
if ($LASTEXITCODE -ne 0) {
  throw "Backend build failed; settlement worker was not started."
}
$worker = Start-Process -FilePath (Get-Command node).Source `
  -ArgumentList "apps/backend/dist/apps/backend/src/workers/financial-worker.js" `
  -WorkingDirectory $workspace -WindowStyle Hidden -PassThru
try {
  & pnpm dev
  exit $LASTEXITCODE
} finally {
  if (-not $worker.HasExited) {
    Stop-Process -Id $worker.Id
  }
}
