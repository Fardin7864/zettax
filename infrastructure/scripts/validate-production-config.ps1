param(
  [Parameter(Mandatory = $true)][string]$EnvFile,
  [switch]$TestNginx,
  [switch]$SingleVps
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$resolvedEnv = (Resolve-Path -LiteralPath $EnvFile).Path
$composeFiles = @(
  (Resolve-Path -LiteralPath "docker-compose.yml").Path,
  (Resolve-Path -LiteralPath "docker-compose.prod.yml").Path
)
if ($SingleVps) {
  $composeFiles += (Resolve-Path -LiteralPath "docker-compose.single-vps.yml").Path
}
$arguments = @("compose", "--env-file", $resolvedEnv)
foreach ($file in $composeFiles) { $arguments += @("-f", $file) }

$rawConfig = & docker @arguments config --format json
if ($LASTEXITCODE -ne 0) { throw "Production Compose configuration is invalid." }
$config = $rawConfig | ConvertFrom-Json

$published = @()
foreach ($serviceProperty in $config.services.PSObject.Properties) {
  $portsProperty = $serviceProperty.Value.PSObject.Properties["ports"]
  if ($portsProperty) {
    foreach ($port in @($portsProperty.Value)) {
      if ($null -ne $port.published) {
        $published += "$($serviceProperty.Name):$($port.published)"
      }
    }
  }
}
$expectedPorts = @("nginx:80", "nginx:443")
if (Compare-Object $expectedPorts $published) {
  throw "Only Nginx ports 80 and 443 may be published. Found: $($published -join ', ')"
}

$expectedNetworks = if ($SingleVps) {
  @{
    postgres = @("data", "operations")
    pgbouncer = @("data")
    redis = @("data", "operations")
    minio = @("data", "operations")
    backend = @("app", "data", "operations")
    "backend-b" = @("app", "data", "operations")
    "financial-worker-a" = @("data", "operations")
    "financial-worker-b" = @("data", "operations")
    admin = @("app", "operations")
    nginx = @("app", "edge", "operations")
    prometheus = @("app", "operations")
    grafana = @("operations")
  }
} else {
  @{
    postgres = @("data")
    redis = @("data")
    minio = @("data")
    backend = @("app", "data")
    admin = @("app")
    nginx = @("app", "edge")
  }
}
foreach ($serviceName in $expectedNetworks.Keys) {
  $actual = @($config.services.$serviceName.networks.PSObject.Properties.Name | Sort-Object)
  $expected = @($expectedNetworks[$serviceName] | Sort-Object)
  if (Compare-Object $expected $actual) {
    throw "$serviceName network membership is unsafe: $($actual -join ', ')"
  }
}
if (-not $config.networks.data.internal) {
  throw "The data network must be internal."
}

$hardenedServices = @("postgres", "redis", "minio", "backend", "admin", "nginx")
if ($SingleVps) {
  $hardenedServices += @("pgbouncer", "backend-b", "financial-worker-a", "financial-worker-b", "prometheus", "grafana", "loki")
}
foreach ($serviceName in $hardenedServices) {
  $service = $config.services.$serviceName
  if (-not $service.read_only) { throw "$serviceName must use a read-only root filesystem." }
  if (-not $service.user -or $service.user -match "^(0|root)(:|$)") {
    throw "$serviceName must run as a non-root user."
  }
  if (@($service.security_opt) -notcontains "no-new-privileges:true") {
    throw "$serviceName must set no-new-privileges."
  }
  if (@($service.cap_drop) -notcontains "ALL") {
    throw "$serviceName must drop all Linux capabilities."
  }
}

if ($SingleVps) {
  if (-not $config.networks.operations.internal) {
    throw "The operations network must be internal."
  }
  if ($config.services.backend.environment.DATABASE_URL -notmatch "@pgbouncer:5432/") {
    throw "Single-VPS backend connections must pass through PgBouncer."
  }
  if ($config.services."backend-b".environment.COMPLIANCE_MODE -ne "DEMO_ONLY") {
    throw "Both API replicas must retain the DEMO_ONLY production baseline."
  }
  foreach ($serviceName in @("postgres", "redis", "minio")) {
    $mounts = @($config.services.$serviceName.volumes | ForEach-Object { $_.source })
    if (-not ($mounts | Where-Object { $_ -match "^/srv/primevest" })) {
      throw "$serviceName must use an explicit /srv/primevest bind mount."
    }
  }
}

$backendEnvironment = $config.services.backend.environment
if ($backendEnvironment.COMPLIANCE_MODE -ne "DEMO_ONLY" -or
    $backendEnvironment.EXECUTION_PROVIDER -ne "MOCK") {
  throw "Validation accepts only the fail-closed DEMO_ONLY/MOCK production baseline."
}
foreach ($flag in @(
    "ENABLE_REAL_TRADING",
    "ENABLE_CRYPTO_TRADING",
    "ENABLE_FOREX_TRADING",
    "ENABLE_STOCK_TRADING",
    "ENABLE_COMMODITY_TRADING",
    "ENABLE_INDEX_TRADING",
    "ENABLE_DEPOSITS",
    "ENABLE_WITHDRAWALS"
  )) {
  if ($backendEnvironment.$flag -ne "false") { throw "$flag must remain false." }
}

$serialized = $rawConfig -join "`n"
if ($serialized -match "(?i)primevest-local-only|primevest-minio-local|change-me|REPLACE_WITH") {
  throw "Rendered production configuration contains a known placeholder/local credential."
}
if ($backendEnvironment.PSObject.Properties["NEXT_PUBLIC_API_URL"]) {
  throw "Public frontend configuration must not be injected into the backend."
}
if (-not $backendEnvironment.CORS_ORIGINS.StartsWith("https://")) {
  throw "Production CORS_ORIGINS must use HTTPS."
}
if (-not $config.services.admin.environment.NEXT_PUBLIC_API_URL.StartsWith("https://")) {
  throw "Production NEXT_PUBLIC_API_URL must use HTTPS."
}

if ($TestNginx) {
  & docker @arguments run --rm --no-deps nginx nginx -t
  if ($LASTEXITCODE -ne 0) { throw "Nginx configuration validation failed." }
}

Write-Output "Production Compose controls validated."
Write-Output "Published ports: $($published -join ', ')"
Write-Output "Real-money baseline: DEMO_ONLY / MOCK / disabled"
