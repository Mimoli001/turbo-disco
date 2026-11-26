#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('migrate', 'verify')]
    [string]$Command = 'migrate'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

$openbot = Join-Path $env:LOCALAPPDATA 'Programs\OpenBot\OpenBot.exe'
$asar = Join-Path $env:LOCALAPPDATA 'Programs\OpenBot\resources\app.asar'
$userData = Join-Path $env:APPDATA 'OpenBot'
$auth = Join-Path $userData 'openbot-central-auth-v1.bin'
$localState = Join-Path $userData 'Local State'
$keyPath = Join-Path $userData 'secret-storage.key'

if (-not (Test-Path -LiteralPath $openbot) -or -not (Test-Path -LiteralPath $asar)) {
    Write-Output '[openbot-storage] OpenBot is not installed; nothing to migrate.'
    exit 0
}
if (-not (Test-Path -LiteralPath $auth)) {
    Write-Output '[openbot-storage] No saved OpenBot account session exists yet.'
    exit 0
}

function Enable-PortableStorage {
    $old = 'const keyFileFallback = linux || platform === "darwin";'
    $statement = 'const keyFileFallback = true;'
    $replacement = $statement.PadRight($old.Length, ' ')
    $bytes = [IO.File]::ReadAllBytes($asar)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    if ($text.Contains($statement)) {
        Write-Output '[openbot-storage] Portable AES-GCM storage is already enabled.'
        return
    }
    $offset = $text.IndexOf($old, [StringComparison]::Ordinal)
    if ($offset -lt 0) {
        throw 'OpenBot secret-storage implementation changed; app.asar was not modified.'
    }
    if ($text.IndexOf($old, $offset + $old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw 'OpenBot secret-storage signature is not unique; app.asar was not modified.'
    }
    $backup = "$asar.openbot-backup"
    if (-not (Test-Path -LiteralPath $backup)) {
        [IO.File]::WriteAllBytes($backup, $bytes)
    }
    $patch = [Text.Encoding]::ASCII.GetBytes($replacement)
    $stream = [IO.File]::Open($asar, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    try {
        $stream.Position = $offset
        $stream.Write($patch, 0, $patch.Length)
        $stream.Flush($true)
    } finally {
        $stream.Dispose()
    }
    Write-Output '[openbot-storage] Portable AES-GCM storage enabled for Windows (original app.asar preserved).'
}

function Read-PortableKey {
    if (-not (Test-Path -LiteralPath $keyPath)) { return $null }
    $key = [Convert]::FromBase64String([IO.File]::ReadAllText($keyPath).Trim())
    if ($key.Length -ne 32) { throw 'The portable OpenBot key is invalid.' }
    return $key
}

function Write-PortableKey {
    $existing = Read-PortableKey
    if ($existing) { return $existing }
    $key = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $temporary = "$keyPath.$PID.tmp"
    [IO.File]::WriteAllText($temporary, [Convert]::ToBase64String($key) + "`n")
    Move-Item -LiteralPath $temporary -Destination $keyPath
    return $key
}

function Unprotect-Portable([byte[]]$Encrypted, [byte[]]$Key) {
    $body = $Encrypted[4..($Encrypted.Length - 1)]
    $nonce = $body[0..11]
    $tag = $body[12..27]
    $ciphertextLength = $body.Length - 28
    $ciphertext = $body[28..(27 + $ciphertextLength)]
    $plaintext = New-Object byte[] $ciphertextLength
    $aes = [Security.Cryptography.AesGcm]::new($Key)
    try {
        $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext)
        return $plaintext
    } finally {
        $aes.Dispose()
    }
}

function Unprotect-OpenBotSession([byte[]]$Encrypted) {
    if ($Encrypted.Length -gt 4 -and [Text.Encoding]::ASCII.GetString($Encrypted[0..3]) -eq 'obk1') {
        $key = Read-PortableKey
        if (-not $key) { throw 'The portable OpenBot key is missing.' }
        return Unprotect-Portable $Encrypted $key
    }
    if ($Encrypted.Length -le 31 -or [Text.Encoding]::ASCII.GetString($Encrypted[0..2]) -ne 'v10') {
        throw 'Unknown OpenBot session encryption format.'
    }
    # Electron safeStorage v10: AES-256-GCM, 12-byte nonce, tag at the end.
    # Its 32-byte key is wrapped with current-user DPAPI in Local State.
    $state = Get-Content -LiteralPath $localState -Raw | ConvertFrom-Json
    $wrapped = [Convert]::FromBase64String($state.os_crypt.encrypted_key)
    if ([Text.Encoding]::ASCII.GetString($wrapped[0..4]) -ne 'DPAPI') {
        throw 'Unexpected OpenBot key wrapping format.'
    }
    $key = [Security.Cryptography.ProtectedData]::Unprotect(
        $wrapped[5..($wrapped.Length - 1)], $null,
        [Security.Cryptography.DataProtectionScope]::CurrentUser)
    try {
        $nonce = $Encrypted[3..14]
        $tag = $Encrypted[($Encrypted.Length - 16)..($Encrypted.Length - 1)]
        $ciphertextLength = $Encrypted.Length - 31
        $ciphertext = $Encrypted[15..(14 + $ciphertextLength)]
        $plaintext = New-Object byte[] $ciphertextLength
        $aes = [Security.Cryptography.AesGcm]::new($key)
        try {
            $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext)
            return $plaintext
        } finally {
            $aes.Dispose()
        }
    } finally {
        [Array]::Clear($key, 0, $key.Length)
    }
}

function Protect-Portable([byte[]]$Plaintext, [byte[]]$Key) {
    $nonce = [Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $tag = New-Object byte[] 16
    $ciphertext = New-Object byte[] $Plaintext.Length
    $aes = [Security.Cryptography.AesGcm]::new($Key)
    try {
        $aes.Encrypt($nonce, $Plaintext, $ciphertext, $tag)
    } finally {
        $aes.Dispose()
    }
    $format = [Text.Encoding]::ASCII.GetBytes('obk1')
    $result = New-Object byte[] (4 + 12 + 16 + $ciphertext.Length)
    [Array]::Copy($format, 0, $result, 0, 4)
    [Array]::Copy($nonce, 0, $result, 4, 12)
    [Array]::Copy($tag, 0, $result, 16, 16)
    [Array]::Copy($ciphertext, 0, $result, 32, $ciphertext.Length)
    return $result
}

$encrypted = [Convert]::FromBase64String([IO.File]::ReadAllText($auth).Trim())
$plaintext = $null
$key = $null
try {
    $plaintext = Unprotect-OpenBotSession $encrypted
    $format = if ([Text.Encoding]::ASCII.GetString($encrypted[0..2]) -eq 'v10') { 'dpapi-v10' } else { 'obk1' }
    if ($Command -eq 'verify') {
        Write-Output ([pscustomobject]@{ status = 'verified'; format = $format } | ConvertTo-Json -Compress)
        exit 0
    }

    Enable-PortableStorage
    $key = Write-PortableKey
    $migrated = Protect-Portable $plaintext $key
    $verified = Unprotect-Portable $migrated $key
    if ([Convert]::ToBase64String($verified) -ne [Convert]::ToBase64String($plaintext)) {
        throw 'Portable OpenBot session verification failed.'
    }
    $temporary = "$auth.$PID.tmp"
    [IO.File]::WriteAllText($temporary, [Convert]::ToBase64String($migrated))
    Move-Item -LiteralPath $temporary -Destination $auth -Force
    Write-Output ([pscustomobject]@{ status = $(if ($format -eq 'obk1') { 'verified' } else { 'migrated' }); format = 'obk1' } | ConvertTo-Json -Compress)
} finally {
    if ($plaintext) { [Array]::Clear($plaintext, 0, $plaintext.Length) }
    if ($key) { [Array]::Clear($key, 0, $key.Length) }
}

$key = Read-PortableKey
if ($key) {
    [Array]::Clear($key, 0, $key.Length)
    & icacls $keyPath /inheritance:r /grant:r "${env:USERNAME}:(F)" *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict the portable OpenBot key ACL.' }
}
Write-Output "[openbot-storage] $Command completed without exposing session contents."
