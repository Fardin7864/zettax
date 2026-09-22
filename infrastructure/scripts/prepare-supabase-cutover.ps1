$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$oldPath = Join-Path $root 'infrastructure\secrets\vps-production.env'
$newPath = Join-Path $root '.env.new-supabase'
$outPath = Join-Path $root 'infrastructure\secrets\vps-production-new.env'
if (-not (Test-Path $oldPath) -or -not (Test-Path $newPath)) {
  throw 'The current VPS environment and new Supabase environment are both required.'
}
$changes = @{}
foreach ($line in Get-Content -LiteralPath $newPath) {
  if ($line -match '^([A-Z0-9_]+)=(.*)$') { $changes[$matches[1]] = $matches[2] }
}
foreach ($required in @('DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_EVIDENCE_BUCKET')) {
  if (-not $changes[$required]) { throw "New environment is missing $required" }
}
$changes['EVIDENCE_STORAGE_PROVIDER'] = 'supabase'
$remove = @('SUPABASE_S3_ENDPOINT','SUPABASE_S3_ACCESS_KEY_ID','SUPABASE_S3_SECRET_ACCESS_KEY','SUPABASE_S3_REGION')
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in Get-Content -LiteralPath $oldPath) {
  if ($line -match '^([A-Z0-9_]+)=') {
    $key = $matches[1]
    if ($remove -contains $key -or $changes.ContainsKey($key)) { continue }
  }
  $lines.Add($line)
}
$lines.Add('# New Zettax production Supabase project')
foreach ($key in $changes.Keys) { $lines.Add("$key=$($changes[$key])") }
[System.IO.File]::WriteAllLines($outPath, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Prepared ignored production environment at $outPath"
