$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$active = Join-Path $root '.env.local'
$backup = Join-Path $root 'infrastructure\secrets\old-local.env'
$new = Join-Path $root '.env.new-supabase'
if (-not (Test-Path $active) -or -not (Test-Path $new)) { throw 'Local and new Supabase environments are required.' }
if (Test-Path $backup) { throw 'Old local environment backup already exists; refusing to overwrite.' }
$changes = @{}
foreach ($line in Get-Content -LiteralPath $new) {
  if ($line -match '^([A-Z0-9_]+)=(.*)$') { $changes[$matches[1]] = $matches[2] }
}
foreach ($required in @('DATABASE_URL','SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_EVIDENCE_BUCKET')) {
  if (-not $changes[$required]) { throw "New environment is missing $required" }
}
$changes['EVIDENCE_STORAGE_PROVIDER'] = 'supabase'
$remove = @('SUPABASE_S3_ENDPOINT','SUPABASE_S3_ACCESS_KEY_ID','SUPABASE_S3_SECRET_ACCESS_KEY','SUPABASE_S3_REGION')
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in Get-Content -LiteralPath $active) {
  if ($line -match '^([A-Z0-9_]+)=') {
    $key = $matches[1]
    if ($changes.ContainsKey($key) -or $remove -contains $key) { continue }
  }
  $lines.Add($line)
}
foreach ($key in $changes.Keys) { $lines.Add("$key=$($changes[$key])") }
Copy-Item -LiteralPath $active -Destination $backup
[System.IO.File]::WriteAllLines($active, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Local development now points to the new Supabase project; old configuration is preserved in the ignored secrets folder.'
