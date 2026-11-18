#Requires -Version 7.5
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packageName = 'construction.ridgeline.smartdock'
$keyAlias = 'smart-dock-release'
if ([string]::IsNullOrWhiteSpace($env:OneDriveCommercial) -or
    -not (Test-Path -LiteralPath $env:OneDriveCommercial -PathType Container)) {
    throw 'OneDriveCommercial must point to an existing signed-in OneDrive folder before creating the release identity.'
}
$releaseIdentityRoot = Join-Path $env:OneDriveCommercial 'ZacsApps\Release Identity'
if (-not (Test-Path -LiteralPath $releaseIdentityRoot -PathType Container)) {
    throw "The OneDrive release identity directory is missing: $releaseIdentityRoot"
}
$recoveryRoot = Join-Path $releaseIdentityRoot 'SmartDock'
$localRoot = Join-Path $env:LOCALAPPDATA 'SmartDock\signing'
$keystorePath = Join-Path $recoveryRoot 'smart-dock-release.p12'
$recoverySecretPath = Join-Path $recoveryRoot 'smart-dock-release-recovery.json'
$publicIdentityPath = Join-Path $recoveryRoot 'smart-dock-release-public.json'
$publicCertificatePath = Join-Path $recoveryRoot 'smart-dock-release-certificate.pem'
$operationalSecretPath = Join-Path $localRoot 'smart-dock-release-current-user.dpapi.json'

function Resolve-Keytool {
    $resolved = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
    if (-not $resolved -or -not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        $command = Get-Command keytool.exe -ErrorAction SilentlyContinue
        if ($command) { $resolved = $command.Source }
    }
    if (-not $resolved) { throw 'A trusted JDK keytool.exe was not found.' }
    return $resolved
}

function New-RandomSecret {
    $bytes = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    try { return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    finally { [System.Security.Cryptography.CryptographicOperations]::ZeroMemory($bytes) }
}

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Protect-RecoveryPayload([string]$PlainText, [string]$Passphrase) {
    $salt = [byte[]]::new(32)
    $nonce = [byte[]]::new(12)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($salt)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
    $iterations = 600000
    $derive = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($Passphrase, $salt, $iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    $key = $derive.GetBytes(32)
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipherBytes = [byte[]]::new($plainBytes.Length)
    $tag = [byte[]]::new(16)
    try {
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        try { $aes.Encrypt($nonce, $plainBytes, $cipherBytes, $tag) } finally { $aes.Dispose() }
        return [ordered]@{
            format = 'smart-dock-recovery-v1'
            kdf = 'PBKDF2-HMAC-SHA256'
            iterations = $iterations
            cipher = 'AES-256-GCM'
            salt = [Convert]::ToBase64String($salt)
            nonce = [Convert]::ToBase64String($nonce)
            ciphertext = [Convert]::ToBase64String($cipherBytes)
            tag = [Convert]::ToBase64String($tag)
        }
    }
    finally {
        $derive.Dispose()
        foreach ($buffer in @($key, $plainBytes, $cipherBytes, $tag, $salt, $nonce)) {
            [System.Security.Cryptography.CryptographicOperations]::ZeroMemory($buffer)
        }
    }
}

function Set-OwnerOnlyAcl([string]$Path) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetOwner([Security.Principal.NTAccount]::new($identity))
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, [Security.AccessControl.FileSystemRights]::FullControl, [Security.AccessControl.AccessControlType]::Allow))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

$ownedTargets = @($keystorePath, $recoverySecretPath, $publicIdentityPath, $publicCertificatePath, $operationalSecretPath)
$existing = $ownedTargets | Where-Object { Test-Path -LiteralPath $_ }
if ($existing) { throw "Release identity initialization stopped: an identity file already exists. Nothing was overwritten.`n$($existing -join "`n")" }

$first = Read-Host 'Create a recovery passphrase for the Smart Dock signing identity' -AsSecureString
$second = Read-Host 'Confirm the recovery passphrase' -AsSecureString
$firstPlain = Convert-SecureStringToPlainText $first
$secondPlain = Convert-SecureStringToPlainText $second
if ($firstPlain.Length -lt 16) { throw 'The recovery passphrase must contain at least 16 characters.' }
$firstBytes = [Text.Encoding]::UTF8.GetBytes($firstPlain)
$secondBytes = [Text.Encoding]::UTF8.GetBytes($secondPlain)
try {
    if (-not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($firstBytes, $secondBytes)) { throw 'The recovery passphrases did not match.' }
} finally {
    [Security.Cryptography.CryptographicOperations]::ZeroMemory($firstBytes)
    [Security.Cryptography.CryptographicOperations]::ZeroMemory($secondBytes)
}

$storePassword = New-RandomSecret
$keyPassword = $storePassword
$created = [Collections.Generic.List[string]]::new()
$completed = $false
$process = $null
$exportProcess = $null
try {
    New-Item -ItemType Directory -Force -Path $recoveryRoot, $localRoot | Out-Null
    $keytool = Resolve-Keytool
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $keytool
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['SMART_DOCK_GENERATED_STORE_PASSWORD'] = $storePassword
    $start.Environment['SMART_DOCK_GENERATED_KEY_PASSWORD'] = $keyPassword
    @('-genkeypair','-noprompt','-alias',$keyAlias,'-keystore',$keystorePath,'-storetype','PKCS12','-storepass:env','SMART_DOCK_GENERATED_STORE_PASSWORD','-keypass:env','SMART_DOCK_GENERATED_KEY_PASSWORD','-keyalg','RSA','-keysize','4096','-sigalg','SHA256withRSA','-validity','10000','-dname','CN=Smart Dock Release, O=Ridgeline Construction, C=US') | ForEach-Object { [void]$start.ArgumentList.Add($_) }
    $created.Add($keystorePath)
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "keytool failed to create the release identity: $stderr" }
    Set-OwnerOnlyAcl $keystorePath

    $export = [Diagnostics.ProcessStartInfo]::new()
    $export.FileName = $keytool
    $export.UseShellExecute = $false
    $export.RedirectStandardOutput = $true
    $export.RedirectStandardError = $true
    $export.Environment['SMART_DOCK_GENERATED_STORE_PASSWORD'] = $storePassword
    @('-exportcert','-rfc','-alias',$keyAlias,'-keystore',$keystorePath,'-storetype','PKCS12','-storepass:env','SMART_DOCK_GENERATED_STORE_PASSWORD','-file',$publicCertificatePath) | ForEach-Object { [void]$export.ArgumentList.Add($_) }
    $created.Add($publicCertificatePath)
    $exportProcess = [Diagnostics.Process]::Start($export)
    $exportOut = $exportProcess.StandardOutput.ReadToEnd()
    $exportError = $exportProcess.StandardError.ReadToEnd()
    $exportProcess.WaitForExit()
    if ($exportProcess.ExitCode -ne 0) { throw "keytool failed to export the public certificate: $exportError" }

    $certificate = [Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificateFromFile($publicCertificatePath)
    try {
        $fingerprint = $certificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256).ToLowerInvariant()
    }
    finally { $certificate.Dispose() }
    $secretPayload = [ordered]@{ format='smart-dock-local-signing-v1'; packageName=$packageName; keyAlias=$keyAlias; storePassword=$storePassword; keyPassword=$keyPassword; keystorePath=$keystorePath; certificateSha256=$fingerprint } | ConvertTo-Json -Compress

    $operationalSecure = ConvertTo-SecureString $secretPayload -AsPlainText -Force
    $created.Add($operationalSecretPath)
    [ordered]@{ format='smart-dock-dpapi-current-user-v1'; protectedPayload=(ConvertFrom-SecureString $operationalSecure) } | ConvertTo-Json | Set-Content -LiteralPath $operationalSecretPath -Encoding utf8NoBOM
    Set-OwnerOnlyAcl $operationalSecretPath

    $created.Add($recoverySecretPath)
    Protect-RecoveryPayload -PlainText $secretPayload -Passphrase $firstPlain | ConvertTo-Json | Set-Content -LiteralPath $recoverySecretPath -Encoding utf8NoBOM
    Set-OwnerOnlyAcl $recoverySecretPath

    $created.Add($publicIdentityPath)
    [ordered]@{ format='smart-dock-public-release-identity-v1'; packageName=$packageName; versionCode=1151; versionName='1.15.0-ridgeline.1'; keyAlias=$keyAlias; certificateSha256=$fingerprint; certificateFile=[IO.Path]::GetFileName($publicCertificatePath); keystoreFile=[IO.Path]::GetFileName($keystorePath); recoveryFile=[IO.Path]::GetFileName($recoverySecretPath); createdAt=[DateTimeOffset]::UtcNow.ToString('O'); custody='Private key stays in the PKCS12 file; operational credentials are DPAPI CurrentUser protected; a recovery copy is passphrase encrypted.' } | ConvertTo-Json | Set-Content -LiteralPath $publicIdentityPath -Encoding utf8NoBOM
    Set-OwnerOnlyAcl $publicIdentityPath

    $completed = $true
    Write-Host 'Smart Dock local release identity created.'
    Write-Host "Public certificate SHA-256: $fingerprint"
    Write-Host "Encrypted recovery directory: $recoveryRoot"
    Write-Host "Current-user operational record: $operationalSecretPath"
}
finally {
    foreach ($child in @($process, $exportProcess)) {
        if ($null -ne $child) {
            if (-not $completed) {
                try {
                    if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit() }
                }
                catch { Write-Warning "Could not stop a keytool process during cleanup: $($_.Exception.Message)" }
            }
            $child.Dispose()
        }
    }
    if (-not $completed) {
        foreach ($target in $created) {
            try {
                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    Remove-Item -LiteralPath $target -Force -ErrorAction Stop
                }
            }
            catch { Write-Warning "Could not remove partial identity file ${target}: $($_.Exception.Message)" }
        }
    }
    $first.Dispose(); $second.Dispose()
    $firstPlain = $null; $secondPlain = $null; $storePassword = $null; $keyPassword = $null; $secretPayload = $null
    [GC]::Collect()
}
