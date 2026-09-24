param(
  [string]$Background = 'apps\mobile\assets\branding\play_feature_background_v1.png'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$backgroundPath = Join-Path $repoRoot $Background
$wordmarkPath = Join-Path $repoRoot 'apps\mobile\assets\branding\zettax_wordmark.png'
$outputPath = Join-Path $repoRoot 'apps\mobile\assets\branding\play_feature_graphic.png'
if (-not (Test-Path $backgroundPath) -or -not (Test-Path $wordmarkPath)) {
  throw 'Feature graphic source assets are missing.'
}

Add-Type -AssemblyName System.Drawing
$backgroundImage = [System.Drawing.Image]::FromFile($backgroundPath)
$wordmarkImage = [System.Drawing.Image]::FromFile($wordmarkPath)
$canvas = [System.Drawing.Bitmap]::new(1024, 500)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
try {
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.DrawImage($backgroundImage, [System.Drawing.Rectangle]::new(0, 0, 1024, 500))
  $graphics.DrawImage($wordmarkImage, [System.Drawing.Rectangle]::new(302, 40, 420, 420))
  $canvas.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $graphics.Dispose()
  $canvas.Dispose()
  $wordmarkImage.Dispose()
  $backgroundImage.Dispose()
}
Write-Host "Created $outputPath (1024x500)"
