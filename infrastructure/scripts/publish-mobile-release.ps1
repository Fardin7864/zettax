param(
  [Parameter(Mandatory = $true)]
  [string]$VersionName,
  [Parameter(Mandatory = $true)]
  [int]$VersionCode,
  [string]$Notes = "Zettax improvements and fixes."
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mobileDir = Join-Path $repoRoot 'apps\mobile'
$pubspec = Get-Content (Join-Path $mobileDir 'pubspec.yaml') -Raw
$expectedVersion = "version: $VersionName+$VersionCode"
if (-not $pubspec.Contains($expectedVersion)) {
  throw "pubspec.yaml must contain $expectedVersion"
}
if ((git -C $repoRoot status --porcelain).Length -ne 0) {
  throw 'Commit and push source changes before publishing an APK.'
}
if ((git -C $repoRoot rev-parse '@{u}') -ne (git -C $repoRoot rev-parse HEAD)) {
  throw 'Push the current commit before publishing an APK.'
}
$flutter = 'H:\tools\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { throw "Flutter not found at $flutter" }
$key = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $key)) { throw 'Original Android signing key is missing. Do not publish an APK with a different key.' }

Push-Location $mobileDir
try { & $flutter build apk --release } finally { Pop-Location }
if ($LASTEXITCODE -ne 0) { throw 'Flutter APK build failed.' }
$apk = Join-Path $mobileDir 'build\app\outputs\flutter-apk\app-release.apk'
$hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
$tag = "v$VersionName"
$assetName = "zettax-$VersionName.apk"
if ((gh release view $tag --repo Fardin7864/zettax 2>$null)) {
  throw "Release $tag already exists; refusing to overwrite a published APK."
}
gh release create $tag "$apk#$assetName" --repo Fardin7864/zettax --target main --title "Zettax $VersionName" --notes $Notes
if ($LASTEXITCODE -ne 0) { throw 'GitHub release creation failed.' }

$manifest = [ordered]@{
  versionName = $VersionName
  versionCode = $VersionCode
  apkUrl = 'https://zettax.app/downloads/zettax-latest.apk'
  sha256 = $hash
  notes = $Notes
} | ConvertTo-Json -Compress
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("zettax-release-$VersionCode")
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
try {
  $manifestPath = Join-Path $tempDir 'latest.json'
  [System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
  scp $apk "root@zettax-vps:/tmp/zettax-$VersionCode.apk"
  if ($LASTEXITCODE -ne 0) { throw 'APK upload to VPS failed.' }
  scp $manifestPath "root@zettax-vps:/tmp/zettax-$VersionCode.json"
  if ($LASTEXITCODE -ne 0) { throw 'Manifest upload to VPS failed.' }
  ssh root@zettax-vps "install -d -m 755 /var/www/zettax/downloads /var/www/zettax/updates && install -m 644 /tmp/zettax-$VersionCode.apk /var/www/zettax/downloads/zettax-latest.apk && install -m 644 /tmp/zettax-$VersionCode.json /var/www/zettax/updates/latest.json && rm /tmp/zettax-$VersionCode.apk /tmp/zettax-$VersionCode.json"
  if ($LASTEXITCODE -ne 0) { throw 'VPS release activation failed.' }
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force
}
Write-Host "Published Zettax $VersionName ($VersionCode); SHA-256 $hash"
