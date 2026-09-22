param([Parameter(Mandatory = $true)][string]$Email, [ValidateSet('operations','funding-reviewer')][string]$Role='operations')
$ErrorActionPreference = 'Stop'
$workspace = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Push-Location -LiteralPath $workspace
$passwordPointer = [IntPtr]::Zero
$confirmationPointer = [IntPtr]::Zero
try {
    Write-Host "Create administrator: $Email"
    Write-Host 'The password is sent over standard input to the local backend container, not stored in a file or command arguments.'
    $securePassword = Read-Host 'New password (at least 16 characters)' -AsSecureString
    $secureConfirmation = Read-Host 'Confirm password' -AsSecureString
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $confirmationPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureConfirmation)
    $adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $adminConfirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationPointer)
    if ($adminPassword.Length -lt 16 -or $adminPassword -cne $adminConfirmation) {
        throw 'Passwords must match and contain at least 16 characters.'
    }
    $payload = @{email = $Email; password = $adminPassword; role = $Role} | ConvertTo-Json -Compress
    $payload | docker compose exec -T -w /workspace/apps/backend backend ./node_modules/.bin/tsx prisma/bootstrap-admin.ts --stdin
    if ($LASTEXITCODE -ne 0) { throw 'Administrator setup failed. No existing administrator password was changed.' }
    Write-Host 'Sign in at http://localhost:3001. Confirm your password before changes; a FIDO2 key is optional.'
} finally {
    if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
    if ($confirmationPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPointer) }
    $adminPassword = $null
    $adminConfirmation = $null
    $payload = $null
    if ($securePassword) { $securePassword.Dispose() }
    if ($secureConfirmation) { $secureConfirmation.Dispose() }
    Pop-Location
}
