param(
  [switch]$CreateUploadKey
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mobileDir = Join-Path $repoRoot 'apps\mobile'
$secretsDir = Join-Path $repoRoot 'infrastructure\secrets'
$keyPath = Join-Path $secretsDir 'zettax-play-upload.jks'
$passwordPath = Join-Path $secretsDir 'zettax-play-upload-password.dpapi'
$flutter = 'H:\tools\flutter\bin\flutter.bat'
$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'

if (-not (Test-Path $flutter) -or -not (Test-Path $keytool)) {
  throw 'Flutter or Android Studio keytool is unavailable.'
}

if ($CreateUploadKey) {
  if ((Test-Path $keyPath) -or (Test-Path $passwordPath)) {
    throw 'An upload key or password already exists. Refusing to replace it.'
  }
  New-Item -ItemType Directory -Force -Path $secretsDir | Out-Null
  $random = New-Object byte[] 48
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
  $env:ZETTAX_PLAY_UPLOAD_PASSWORD = [Convert]::ToBase64String($random)
  try {
    & $keytool -genkeypair -v -keystore $keyPath -storetype PKCS12 -alias zettax-upload `
      -keyalg RSA -keysize 4096 -validity 10000 `
      -dname 'CN=Zettax Upload, OU=Mobile, O=Kodzie, C=BD' `
      '-storepass:env' ZETTAX_PLAY_UPLOAD_PASSWORD '-keypass:env' ZETTAX_PLAY_UPLOAD_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Upload key generation failed.' }
    $protected = ConvertTo-SecureString $env:ZETTAX_PLAY_UPLOAD_PASSWORD -AsPlainText -Force | ConvertFrom-SecureString
    [System.IO.File]::WriteAllText($passwordPath, $protected)
  } finally {
    Remove-Item Env:ZETTAX_PLAY_UPLOAD_PASSWORD -ErrorAction SilentlyContinue
    [Array]::Clear($random, 0, $random.Length)
  }
  Write-Host "Created upload key at $keyPath. Back up the key and DPAPI-protected password together."
}

if (-not (Test-Path $keyPath) -or -not (Test-Path $passwordPath)) {
  throw 'The upload key is missing. Run this script once with -CreateUploadKey.'
}

$protected = [System.IO.File]::ReadAllText($passwordPath)
$secure = ConvertTo-SecureString $protected
$credential = [pscredential]::new('zettax-upload', $secure)
$env:ZETTAX_PLAY_UPLOAD_PASSWORD = $credential.GetNetworkCredential().Password
$env:ZETTAX_PLAY_UPLOAD_KEYSTORE = $keyPath
$env:ZETTAX_ANDROID_DISTRIBUTION = 'play'
try {
  Push-Location $mobileDir
  try {
    & $flutter build appbundle --release --flavor play --dart-define=ZETTAX_DISTRIBUTION=play
    if ($LASTEXITCODE -ne 0) { throw 'Play App Bundle build failed.' }
  } finally {
    Pop-Location
  }
} finally {
  Remove-Item Env:ZETTAX_PLAY_UPLOAD_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:ZETTAX_PLAY_UPLOAD_KEYSTORE -ErrorAction SilentlyContinue
  Remove-Item Env:ZETTAX_ANDROID_DISTRIBUTION -ErrorAction SilentlyContinue
}
$bundle = Join-Path $mobileDir 'build\app\outputs\bundle\playRelease\app-play-release.aab'
if (-not (Test-Path $bundle)) { throw "Missing expected App Bundle: $bundle" }
Write-Host "Play App Bundle: $bundle"
