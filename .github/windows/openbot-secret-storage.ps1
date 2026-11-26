#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('export', 'rebind', 'verify')]
    [string]$Command = 'verify',
    [string]$UserData = (Join-Path $env:APPDATA 'OpenBot')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security.Cryptography.ProtectedData

$auth = Join-Path $userData 'openbot-central-auth-v1.bin'
$portable = Join-Path $userData 'openbot-central-auth-v1.portable'
$localState = Join-Path $userData 'Local State'
$keyPath = Join-Path $userData 'secret-storage.key'

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
    if ($Encrypted.Length -le 32 -or [Text.Encoding]::ASCII.GetString($Encrypted[0..3]) -ne 'obk1') {
        throw 'Unknown portable OpenBot session format.'
    }
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

function Read-SystemKey([switch]$Create) {
    $state = $null
    if (Test-Path -LiteralPath $localState) {
        try { $state = Get-Content -LiteralPath $localState -Raw | ConvertFrom-Json } catch { $state = $null }
    }
    if ($state -and $state.PSObject.Properties['os_crypt'] -and $state.os_crypt.PSObject.Properties['encrypted_key']) {
        $wrapped = [Convert]::FromBase64String($state.os_crypt.encrypted_key)
        if ($wrapped.Length -gt 5 -and [Text.Encoding]::ASCII.GetString($wrapped[0..4]) -eq 'DPAPI') {
            try {
                return [Security.Cryptography.ProtectedData]::Unprotect(
                    $wrapped[5..($wrapped.Length - 1)], $null,
                    [Security.Cryptography.DataProtectionScope]::CurrentUser)
            } catch {
                if (-not $Create) { throw }
            }
        }
    }
    if (-not $Create) { throw 'OpenBot Local State has no usable encryption key.' }

    # A restored Local State belongs to the old machine. Preserve its other
    # settings but generate and DPAPI-wrap a fresh key for this Windows user.
    $key = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $wrapped = [Security.Cryptography.ProtectedData]::Protect(
        $key, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    if (-not $state) { $state = [pscustomobject]@{} }
    $prefix = [Text.Encoding]::ASCII.GetBytes('DPAPI')
    $wrappedWithPrefix = New-Object byte[] (5 + $wrapped.Length)
    [Array]::Copy($prefix, 0, $wrappedWithPrefix, 0, 5)
    [Array]::Copy($wrapped, 0, $wrappedWithPrefix, 5, $wrapped.Length)
    $encoded = [Convert]::ToBase64String($wrappedWithPrefix)
    if ($state.PSObject.Properties['os_crypt']) {
        $state.os_crypt.encrypted_key = $encoded
    } else {
        $state | Add-Member -MemberType NoteProperty -Name os_crypt -Value ([pscustomobject]@{ encrypted_key = $encoded })
    }
    $temporary = "$localState.$PID.tmp"
    [IO.File]::WriteAllText($temporary, ($state | ConvertTo-Json -Depth 20 -Compress))
    Move-Item -LiteralPath $temporary -Destination $localState -Force
    return $key
}

function Unprotect-V10([byte[]]$Encrypted, [byte[]]$Key) {
    if ($Encrypted.Length -le 31 -or [Text.Encoding]::ASCII.GetString($Encrypted[0..2]) -ne 'v10') {
        throw 'Unknown Electron safeStorage format.'
    }
    $nonce = $Encrypted[3..14]
    $tag = $Encrypted[($Encrypted.Length - 16)..($Encrypted.Length - 1)]
    $ciphertextLength = $Encrypted.Length - 31
    $ciphertext = $Encrypted[15..(14 + $ciphertextLength)]
    $plaintext = New-Object byte[] $ciphertextLength
    $aes = [Security.Cryptography.AesGcm]::new($Key)
    try {
        $aes.Decrypt($nonce, $ciphertext, $tag, $plaintext)
        return $plaintext
    } finally {
        $aes.Dispose()
    }
}

function Protect-V10([byte[]]$Plaintext, [byte[]]$Key) {
    $nonce = [Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $tag = New-Object byte[] 16
    $ciphertext = New-Object byte[] $Plaintext.Length
    $aes = [Security.Cryptography.AesGcm]::new($Key)
    try {
        $aes.Encrypt($nonce, $Plaintext, $ciphertext, $tag)
    } finally {
        $aes.Dispose()
    }
    $format = [Text.Encoding]::ASCII.GetBytes('v10')
    $result = New-Object byte[] (3 + 12 + $ciphertext.Length + 16)
    [Array]::Copy($format, 0, $result, 0, 3)
    [Array]::Copy($nonce, 0, $result, 3, 12)
    [Array]::Copy($ciphertext, 0, $result, 15, $ciphertext.Length)
    [Array]::Copy($tag, 0, $result, 15 + $ciphertext.Length, 16)
    return $result
}

function Assert-Equal([byte[]]$Left, [byte[]]$Right) {
    if ([Convert]::ToBase64String($Left) -ne [Convert]::ToBase64String($Right)) {
        throw 'OpenBot session verification failed.'
    }
}

$plaintext = $null
$key = $null
try {
    if ($Command -eq 'export') {
        if (-not (Test-Path -LiteralPath $auth)) {
            Write-Output '[openbot-storage] No saved OpenBot account session exists yet.'
            exit 0
        }
        $encrypted = [Convert]::FromBase64String([IO.File]::ReadAllText($auth).Trim())
        $prefix = [Text.Encoding]::ASCII.GetString($encrypted[0..2])
        if ($prefix -eq 'v10') {
            $systemKey = Read-SystemKey
            try { $plaintext = Unprotect-V10 $encrypted $systemKey }
            finally { [Array]::Clear($systemKey, 0, $systemKey.Length) }
        } else {
            $key = Read-PortableKey
            $plaintext = Unprotect-Portable $encrypted $key
        }
        $key = Write-PortableKey
        $migrated = Protect-Portable $plaintext $key
        Assert-Equal (Unprotect-Portable $migrated $key) $plaintext
        $temporary = "$portable.$PID.tmp"
        [IO.File]::WriteAllText($temporary, [Convert]::ToBase64String($migrated))
        Move-Item -LiteralPath $temporary -Destination $portable -Force
        Write-Output '[openbot-storage] Portable session exported; the original v10 session was not modified.'
    } elseif ($Command -eq 'rebind') {
        if (-not (Test-Path -LiteralPath $portable)) {
            Write-Output '[openbot-storage] No portable OpenBot account session exists.'
            exit 0
        }
        $encrypted = [Convert]::FromBase64String([IO.File]::ReadAllText($portable).Trim())
        $key = Read-PortableKey
        $plaintext = Unprotect-Portable $encrypted $key
        $systemKey = Read-SystemKey -Create
        try {
            $rebound = Protect-V10 $plaintext $systemKey
            Assert-Equal (Unprotect-V10 $rebound $systemKey) $plaintext
        } finally {
            [Array]::Clear($systemKey, 0, $systemKey.Length)
        }
        $temporary = "$auth.$PID.tmp"
        [IO.File]::WriteAllText($temporary, [Convert]::ToBase64String($rebound))
        Move-Item -LiteralPath $temporary -Destination $auth -Force
        Write-Output '[openbot-storage] Session rebound to this Windows user with v10 AES-256-GCM.'
    } else {
        if (Test-Path -LiteralPath $auth) {
            $encrypted = [Convert]::FromBase64String([IO.File]::ReadAllText($auth).Trim())
            $systemKey = Read-SystemKey
            try { $plaintext = Unprotect-V10 $encrypted $systemKey }
            finally { [Array]::Clear($systemKey, 0, $systemKey.Length) }
            Write-Output '{"status":"verified","format":"v10"}'
        }
        if (Test-Path -LiteralPath $portable) {
            $encrypted = [Convert]::FromBase64String([IO.File]::ReadAllText($portable).Trim())
            $key = Read-PortableKey
            $plaintext = Unprotect-Portable $encrypted $key
            Write-Output '{"status":"verified","format":"obk1"}'
        }
    }
} finally {
    if ($plaintext) { [Array]::Clear($plaintext, 0, $plaintext.Length) }
    if ($key) { [Array]::Clear($key, 0, $key.Length) }
}

$key = Read-PortableKey
if ($key) {
    [Array]::Clear($key, 0, $key.Length)
    & icacls $keyPath /inheritance:r /grant:r "${env:USERNAME}:(F)" *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict the portable OpenBot key ACL.' }
    & icacls $portable /inheritance:r /grant:r "${env:USERNAME}:(F)" *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict the portable OpenBot session ACL.' }
}
Write-Output "[openbot-storage] $Command completed without exposing session contents."
