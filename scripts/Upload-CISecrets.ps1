[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = 'Ridgeline-Tech/smartdock'
$expectedPackage = 'construction.ridgeline.smartdock'
$localRecord = Join-Path $env:LOCALAPPDATA 'SmartDock\signing\smart-dock-release-current-user.dpapi.json'
$publicRecord = Join-Path (Join-Path $env:USERPROFILE 'OneDrive - Ridgeline Construction\ZacsApps\Release Identity\SmartDock') 'smart-dock-release-public.json'

function Set-ActionSecret([string]$GhPath, [string]$Name, [string]$Value) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $GhPath
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    @('secret', 'set', $Name, '--app', 'actions', '--repo', $repo) | ForEach-Object { [void]$start.ArgumentList.Add($_) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $null = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "GitHub rejected secret $Name (exit $($process.ExitCode)); inspect authentication and repository access before retrying." }
        Write-Host "Uploaded $Name to $repo Actions secrets."
    }
    finally { $process.Dispose() }
}

if (-not (Test-Path -LiteralPath $localRecord -PathType Leaf) -or -not (Test-Path -LiteralPath $publicRecord -PathType Leaf)) {
    throw 'The dedicated Smart Dock identity records are missing. Run Initialize-ReleaseIdentity.ps1 interactively first.'
}

$gh = (Get-Command gh -ErrorAction Stop).Source
$identity = gh api "repos/$repo" --jq '.full_name'
if ($LASTEXITCODE -ne 0 -or $identity -ne $repo) { throw "GitHub target verification failed for $repo." }

$wrapped = Get-Content -LiteralPath $localRecord -Raw | ConvertFrom-Json
$public = Get-Content -LiteralPath $publicRecord -Raw | ConvertFrom-Json
if ($wrapped.format -ne 'smart-dock-dpapi-current-user-v1' -or $public.format -ne 'smart-dock-public-release-identity-v1') {
    throw 'Smart Dock signing record format mismatch.'
}
$secure = ConvertTo-SecureString $wrapped.protectedPayload
$plain = [Net.NetworkCredential]::new('', $secure).Password
$payload = $plain | ConvertFrom-Json
if ($payload.format -ne 'smart-dock-local-signing-v1' -or $payload.packageName -ne $expectedPackage -or
    $public.packageName -ne $expectedPackage -or $payload.keyAlias -ne $public.keyAlias -or
    $payload.certificateSha256 -ne $public.certificateSha256 -or
    $payload.certificateSha256 -notmatch '^[0-9a-f]{64}$' -or
    -not (Test-Path -LiteralPath $payload.keystorePath -PathType Leaf)) {
    throw 'Smart Dock signing identity did not match its public record or keystore path.'
}

$bytes = [IO.File]::ReadAllBytes($payload.keystorePath)
try {
    $base64 = [Convert]::ToBase64String($bytes)
    Set-ActionSecret $gh 'SMART_DOCK_RELEASE_KEYSTORE_BASE64' $base64
    Set-ActionSecret $gh 'SMART_DOCK_RELEASE_STORE_PASSWORD' $payload.storePassword
    Set-ActionSecret $gh 'SMART_DOCK_RELEASE_KEY_ALIAS' $payload.keyAlias
    Set-ActionSecret $gh 'SMART_DOCK_RELEASE_KEY_PASSWORD' $payload.keyPassword
    Set-ActionSecret $gh 'SMART_DOCK_RELEASE_CERT_SHA256' $payload.certificateSha256
    Write-Host "Smart Dock CI signing identity is configured. Public certificate SHA-256: $($payload.certificateSha256)"
}
finally {
    [Security.Cryptography.CryptographicOperations]::ZeroMemory($bytes)
    $base64 = $null
    $plain = $null
    $payload = $null
    $secure.Dispose()
    [GC]::Collect()
}
