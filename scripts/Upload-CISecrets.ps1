[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = 'github.com/Ridgeline-Tech/smartdock'
$apiRepo = 'Ridgeline-Tech/smartdock'
$expectedPackage = 'construction.ridgeline.smartdock'
$localRecord = Join-Path $env:LOCALAPPDATA 'SmartDock\signing\smart-dock-release-current-user.dpapi.json'
if ([string]::IsNullOrWhiteSpace($env:OneDriveCommercial) -or
    -not (Test-Path -LiteralPath $env:OneDriveCommercial -PathType Container)) {
    throw 'OneDriveCommercial must point to the existing signed-in OneDrive folder containing the release identity.'
}
$publicRecord = Join-Path (Join-Path $env:OneDriveCommercial 'ZacsApps\Release Identity\SmartDock') 'smart-dock-release-public.json'

function Set-ActionSecret([string]$GhPath, [string]$Name, [string]$Value) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $GhPath
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    @('secret', 'set', $Name, '--env', 'smart-dock-release', '--repo', $repo) | ForEach-Object { [void]$start.ArgumentList.Add($_) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $null = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "GitHub rejected secret $Name (exit $($process.ExitCode)); inspect authentication and repository access before retrying." }
        Write-Host "Uploaded $Name to the $repo smart-dock-release Environment."
    }
    finally { $process.Dispose() }
}

if (-not (Test-Path -LiteralPath $localRecord -PathType Leaf) -or -not (Test-Path -LiteralPath $publicRecord -PathType Leaf)) {
    throw 'The dedicated Smart Dock identity records are missing. Run Initialize-ReleaseIdentity.ps1 interactively first.'
}

$gh = (Get-Command gh -ErrorAction Stop).Source
$identity = & $gh api --hostname github.com "repos/$apiRepo" --jq '.full_name'
if ($LASTEXITCODE -ne 0 -or $identity -ne $apiRepo) { throw "GitHub target verification failed for $repo." }
$environment = & $gh api --hostname github.com "repos/$apiRepo/environments/smart-dock-release" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $environment.name -ne 'smart-dock-release' -or
    -not $environment.deployment_branch_policy.custom_branch_policies) {
    throw 'The protected Smart Dock GitHub Environment is missing or no longer uses custom branch restrictions.'
}
$reviewerRules = @($environment.protection_rules | Where-Object { $_.type -eq 'required_reviewers' })
if ($reviewerRules.Count -ne 1 -or $reviewerRules[0].reviewers.Count -ne 1 -or
    $reviewerRules[0].reviewers[0].type -ne 'User' -or
    $reviewerRules[0].reviewers[0].reviewer.login -ne 'Wabull') {
    throw 'The Smart Dock Environment must require Zac (Wabull) as its sole reviewer.'
}
$branchPolicies = & $gh api --hostname github.com "repos/$apiRepo/environments/smart-dock-release/deployment-branch-policies" | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $branchPolicies.total_count -ne 1 -or
    $branchPolicies.branch_policies[0].name -ne 'main') {
    throw 'The Smart Dock Environment must allow only the main deployment branch.'
}

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
