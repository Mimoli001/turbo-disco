#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('restore', 'verify', 'save', 'hold', 'final', 'status')]
    [string]$Command,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:Repo = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { 'Mimoli001/turbo-disco' }
$script:Tag = if ($env:STATE_TAG) { $env:STATE_TAG } else { 'windows-state' }
$script:WorkRoot = if ($env:STATE_WORK) { $env:STATE_WORK } else { 'D:\windows-state-work' }
$script:PassphraseFile = if ($env:STATE_PASSPHRASE_FILE) { $env:STATE_PASSPHRASE_FILE } else { 'D:\windows-state-local\passphrase' }
$script:ProfileRoot = $env:USERPROFILE
$script:ChunkBytes = 1900MB
$script:Keep = 3
$script:SaveEvery = if ($env:SAVE_EVERY) { [int]$env:SAVE_EVERY } else { 900 }
$script:SessionSeconds = if ($env:SESSION_SECONDS) { [int]$env:SESSION_SECONDS } else { 19200 }
$script:JobStart = if ($env:JOB_START) { [long]$env:JOB_START } else { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$script:RestoreMarker = Join-Path $script:WorkRoot 'restore.ok'
$script:FingerprintFile = Join-Path $script:WorkRoot 'last.fp'
$script:ExcludedPrefixes = @(
    'AppData/Local/Temp',
    'AppData/Local/CrashDumps',
    'AppData/Local/Microsoft/Windows/INetCache',
    'AppData/Local/Microsoft/Windows/Explorer',
    # App execution aliases are machine-specific reparse points, not user data.
    'AppData/Local/Microsoft/WindowsApps',
    'AppData/Local/pip/Cache',
    '.cache',
    '.npm/_cacache'
)
$script:CacheNames = @('Cache', 'Code Cache', 'GPUCache', 'ShaderCache', 'GrShaderCache')

function Log([string]$Message) {
    Write-Host "[windows-state] $Message"
}

function Invoke-Exe {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @(),
        [int[]]$SuccessCodes = @(0)
    )
    & $File @Arguments
    $code = $LASTEXITCODE
    if ($SuccessCodes -notcontains $code) {
        throw "$File exited with code $code"
    }
}

function Reset-WorkPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($script:WorkRoot).TrimEnd('\') + '\'
    if (-not ($full + '\').StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside $root"
    }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    New-Item -ItemType Directory -Path $full -Force | Out-Null
}

function Initialize-State {
    New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
    if (-not $env:STATE_PASSPHRASE -and (Test-Path -LiteralPath $script:PassphraseFile)) {
        $env:STATE_PASSPHRASE = [IO.File]::ReadAllText($script:PassphraseFile).Trim()
    }
    if (-not $env:STATE_PASSPHRASE) {
        throw 'STATE_PASSPHRASE is required.'
    }
    foreach ($tool in 'gh', 'tar', 'zstd', 'openssl', 'robocopy', 'reg') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required tool not found: $tool"
        }
    }
}

function Get-ReleaseAssets {
    $result = & gh release view $script:Tag -R $script:Repo --json assets 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $message = $result | Out-String
        # Only this confirmed case means "no snapshots". Network errors,
        # permission failures and malformed responses must fail closed.
        if ($message -match 'release not found') { return @() }
        throw "Could not list checkpoint assets: $message"
    }
    try {
        return @(($result | Out-String | ConvertFrom-Json).assets)
    } catch {
        throw "Checkpoint asset listing was not valid JSON: $($_.Exception.Message)"
    }
}

function Ensure-Release {
    if (@(Get-ReleaseAssets).Count -eq 0) {
        & gh release view $script:Tag -R $script:Repo *> $null
        if ($LASTEXITCODE -ne 0) {
            Invoke-Exe gh @('release', 'create', $script:Tag, '-R', $script:Repo,
                '--title', 'Windows state (encrypted)',
                '--notes', 'Auto-managed encrypted Windows checkpoints. Do not edit manually.',
                '--latest=false')
        }
    }
}

function Get-SnapshotStamps {
    return @(Get-ReleaseAssets | ForEach-Object {
        if ($_.name -match '^state-(\d+)\.done\.json$') { $Matches[1] }
    } | Sort-Object -Descending -Unique)
}

function Test-Excluded([string]$Path) {
    $relative = [IO.Path]::GetRelativePath($script:ProfileRoot, $Path).Replace('\', '/')
    foreach ($prefix in $script:ExcludedPrefixes) {
        if ($relative -eq $prefix -or $relative.StartsWith($prefix + '/', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    foreach ($part in $relative.Split('/')) {
        if ($script:CacheNames -contains $part) { return $true }
    }
    return $false
}

function Get-StateFingerprint {
    $hash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    try {
        $files = Get-ChildItem -LiteralPath $script:ProfileRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and -not (Test-Excluded $_.FullName) } |
            Sort-Object FullName
        foreach ($file in $files) {
            $relative = [IO.Path]::GetRelativePath($script:ProfileRoot, $file.FullName)
            $line = "$relative|$($file.Length)|$($file.LastWriteTimeUtc.Ticks)`n"
            $bytes = [Text.Encoding]::UTF8.GetBytes($line)
            $hash.AppendData($bytes)
        }
        # Application installs and registry-only changes must also trigger a
        # checkpoint even when no profile file timestamp changed.
        $hive = Join-Path $script:WorkRoot 'fingerprint-hkcu.reg'
        try {
            & reg export HKCU $hive /y *> $null
            if ($LASTEXITCODE -eq 0) {
                $registryBytes = [IO.File]::ReadAllBytes($hive)
                $hash.AppendData($registryBytes)
            }
        } finally {
            Remove-Item -LiteralPath $hive -Force -ErrorAction SilentlyContinue
        }
        $inventory = @(Get-ItemProperty @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        ) -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation |
            ConvertTo-Json -Compress)
        $packageState = @($inventory)
        if (Get-Command python -ErrorAction SilentlyContinue) {
            $packageState += & python -m pip freeze --user 2>$null
        }
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            $packageState += & npm list -g --depth=0 --json 2>$null
        }
        $metadataBytes = [Text.Encoding]::UTF8.GetBytes(($packageState -join "`n"))
        $hash.AppendData($metadataBytes)
        return [Convert]::ToHexString($hash.GetHashAndReset()).ToLowerInvariant()
    } finally {
        $hash.Dispose()
    }
}

function New-ShadowCopy {
    try {
        $result = Invoke-CimMethod -ClassName Win32_ShadowCopy -MethodName Create -Arguments @{
            Volume = 'C:\'
            Context = 'ClientAccessible'
        }
        if ($result.ReturnValue -ne 0) { throw "VSS return code $($result.ReturnValue)" }
        $shadow = Get-CimInstance Win32_ShadowCopy -Filter "ID='$($result.ShadowID)'"
        Log "VSS snapshot created for a consistent copy of locked files."
        return $shadow
    } catch {
        Log "WARNING: VSS unavailable; copying live files instead: $($_.Exception.Message)"
        return $null
    }
}

function Remove-ShadowCopy($Shadow) {
    if ($null -eq $Shadow) { return }
    try {
        Remove-CimInstance -InputObject $Shadow
        Log 'VSS snapshot removed.'
    } catch {
        Log "WARNING: could not remove VSS snapshot: $($_.Exception.Message)"
    }
}

function Copy-ProfileFromSource([string]$Source, [string]$Destination, [switch]$PruneCaches, [switch]$ForRestore) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $excluded = @($script:ExcludedPrefixes | ForEach-Object {
        Join-Path $Source ($_.Replace('/', '\'))
    })
    $retries = if ($ForRestore) { '/R:0' } else { '/R:1' }
    $copyArgs = @($Source, $Destination, '/E', '/B', '/COPY:DAT', '/DCOPY:T', '/XJ',
        $retries, '/W:1', '/NP', '/NFL', '/NDL', '/NJH', '/NJS')
    if ($excluded.Count -gt 0) { $copyArgs += '/XD'; $copyArgs += $excluded }
    if ($ForRestore) {
        # These hives belong to the logged-on runner account and cannot be
        # overwritten in place. HKCU.reg is imported separately below.
        $copyArgs += '/XF'
        $copyArgs += @('NTUSER.DAT', 'NTUSER.DAT*', 'ntuser.dat.*', 'UsrClass.dat', 'UsrClass.dat*',
            'WebCacheLock.dat')
    }
    & robocopy @copyArgs
    $code = $LASTEXITCODE
    if ($code -ge 4 -and $code -le 7) {
        throw "robocopy reported mismatched files (code $code)"
    }
    if ($code -ge 8) {
        if (-not $ForRestore) { throw "robocopy exited with code $code" }
        # Windows owns and memory-maps several built-in app databases for the
        # lifetime of the runner session. Keep every file that can be replaced
        # and report skipped machine-specific files instead of losing the whole
        # restore. Browser and user application data is normally not locked at
        # this early point in the workflow.
        Log "WARNING: Robocopy code $code during restore; files locked by Windows were skipped (details above)."
    }
    if ($PruneCaches) {
        Get-ChildItem -LiteralPath $Destination -Recurse -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $script:CacheNames -contains $_.Name } |
            Sort-Object { $_.FullName.Length } -Descending |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Export-Metadata([string]$Metadata) {
    $registry = Join-Path $Metadata 'Registry'
    $packages = Join-Path $Metadata 'Packages'
    $system = Join-Path $Metadata 'System'
    New-Item -ItemType Directory -Path $registry, $packages, $system -Force | Out-Null

    Invoke-Exe reg @('export', 'HKCU', (Join-Path $registry 'HKCU.reg'), '/y')
    foreach ($entry in @(
        @('HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'Uninstall64.reg'),
        @('HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'Uninstall32.reg')
    )) {
        & reg export $entry[0] (Join-Path $registry $entry[1]) /y *> $null
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget export --output (Join-Path $packages 'winget.json') --include-versions --accept-source-agreements --disable-interactivity *> $null
        & winget list --accept-source-agreements --disable-interactivity |
            Out-File -LiteralPath (Join-Path $packages 'winget-list.txt') -Encoding utf8
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        & choco list --limit-output | Out-File -LiteralPath (Join-Path $packages 'choco.txt') -Encoding utf8
    }
    if (Get-Command python -ErrorAction SilentlyContinue) {
        & python -m pip freeze --user 2>$null | Out-File -LiteralPath (Join-Path $packages 'pip-user.txt') -Encoding utf8
    }
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        & npm list -g --depth=0 --json 2>$null | Out-File -LiteralPath (Join-Path $packages 'npm-global.json') -Encoding utf8
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = @(Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString)
    $apps | ConvertTo-Json -Depth 3 | Out-File -LiteralPath (Join-Path $system 'installed-apps.json') -Encoding utf8
    Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, Version, BuildNumber, OSArchitecture |
        ConvertTo-Json | Out-File -LiteralPath (Join-Path $system 'windows.json') -Encoding utf8
    Get-CimInstance Win32_Service | Select-Object Name, DisplayName, State, StartMode, PathName |
        ConvertTo-Json -Depth 3 | Out-File -LiteralPath (Join-Path $system 'services.json') -Encoding utf8
    Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskName, TaskPath, State |
        ConvertTo-Json -Depth 3 | Out-File -LiteralPath (Join-Path $system 'scheduled-tasks.json') -Encoding utf8
}

function Get-ChunkHmac([string]$Path) {
    # Encrypt-then-MAC: SHA-256 detects accidental damage, while this keyed
    # HMAC also prevents a modified release manifest from authenticating
    # attacker-supplied chunks without STATE_PASSPHRASE.
    $keyMaterial = [Text.Encoding]::UTF8.GetBytes("windows-state-hmac-v1`0$env:STATE_PASSPHRASE")
    $key = [Security.Cryptography.SHA256]::HashData($keyMaterial)
    $hmac = [Security.Cryptography.HMACSHA256]::new($key)
    $stream = [IO.File]::OpenRead($Path)
    try {
        return [Convert]::ToHexString($hmac.ComputeHash($stream)).ToLowerInvariant()
    } finally {
        $stream.Dispose()
        $hmac.Dispose()
    }
}

function Split-EncryptedFile([string]$InputFile, [string]$OutputPrefix, [string]$OutputDirectory) {
    $inputStream = [IO.File]::OpenRead($InputFile)
    $buffer = New-Object byte[] 8MB
    $chunks = @()
    try {
        $index = 0
        while ($inputStream.Position -lt $inputStream.Length) {
            $path = '{0}{1:D3}' -f $OutputPrefix, $index
            $outputStream = [IO.File]::Create($path)
            $remaining = $script:ChunkBytes
            try {
                while ($remaining -gt 0) {
                    $wanted = [int][Math]::Min($buffer.Length, $remaining)
                    $read = $inputStream.Read($buffer, 0, $wanted)
                    if ($read -eq 0) { break }
                    $outputStream.Write($buffer, 0, $read)
                    $remaining -= $read
                }
            } finally {
                $outputStream.Dispose()
            }
            $chunks += Get-Item -LiteralPath $path
            $index++
        }
    } finally {
        $inputStream.Dispose()
    }
    return $chunks
}

function Join-EncryptedChunks([string]$Destination, [string[]]$Paths) {
    $outputStream = [IO.File]::Create($Destination)
    $buffer = New-Object byte[] 8MB
    try {
        foreach ($path in $Paths) {
            $inputStream = [IO.File]::OpenRead($path)
            try {
                while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $outputStream.Write($buffer, 0, $read)
                }
            } finally {
                $inputStream.Dispose()
            }
        }
    } finally {
        $outputStream.Dispose()
    }
}

function Save-State {
    Initialize-State
    if (-not (Test-Path -LiteralPath $script:RestoreMarker)) {
        throw 'Refusing to save: restore has not completed successfully in this run.'
    }
    $mutex = New-Object Threading.Mutex($false, 'Local\TurboDiscoWindowsStateSave')
    $locked = $false
    $root = $null
    try {
        $locked = $mutex.WaitOne([TimeSpan]::FromSeconds(90))
        if (-not $locked) { throw 'Another checkpoint is still running.' }
        $openbotStorage = Join-Path $PSScriptRoot 'openbot-secret-storage.ps1'
        if (Test-Path -LiteralPath $openbotStorage) {
            try {
                & $openbotStorage migrate
            } catch {
                Log "WARNING: OpenBot portable-session migration failed: $($_.Exception.Message)"
            }
        }
        $fingerprint = Get-StateFingerprint
        if (-not $Force -and (Test-Path -LiteralPath $script:FingerprintFile) -and
            [IO.File]::ReadAllText($script:FingerprintFile).Trim() -eq $fingerprint) {
            Log 'No profile changes since the last verified checkpoint; upload skipped.'
            return
        }

        $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $root = Join-Path $script:WorkRoot "save-$timestamp"
        Reset-WorkPath $root
        $stage = Join-Path $root 'stage'
        $output = Join-Path $root 'output'
        $metadata = Join-Path $stage 'Metadata'
        New-Item -ItemType Directory -Path $stage, $output, $metadata -Force | Out-Null
        $shadow = $null
        $shadowLink = $null
        try {
            $shadow = New-ShadowCopy
            if ($shadow) {
                # Robocopy rejects a direct GLOBALROOT source. A directory
                # symbolic link exposes the same read-only shadow as a normal path.
                $shadowLink = Join-Path $script:WorkRoot "shadow-$timestamp"
                & cmd /c mklink /d $shadowLink "$($shadow.DeviceObject)\" *> $null
                if ($LASTEXITCODE -ne 0) { throw 'Could not map the VSS snapshot to a local path.' }
                $source = Join-Path $shadowLink 'Users\runneradmin'
            } else {
                $source = $script:ProfileRoot
            }
            Copy-ProfileFromSource $source (Join-Path $stage 'Profile') -PruneCaches
        } finally {
            if ($shadowLink -and (Test-Path -LiteralPath $shadowLink)) {
                Remove-Item -LiteralPath $shadowLink -Force
            }
            Remove-ShadowCopy $shadow
        }
        Export-Metadata $metadata
        @{
            version = 1
            createdUtc = [DateTimeOffset]::UtcNow.ToString('o')
            timestamp = $timestamp
            profile = $script:ProfileRoot
            computer = $env:COMPUTERNAME
            chunkBytes = $script:ChunkBytes
        } | ConvertTo-Json | Out-File -LiteralPath (Join-Path $metadata 'snapshot.json') -Encoding utf8

        $tar = Join-Path $root 'state.tar'
        $zst = Join-Path $root 'state.tar.zst'
        $encrypted = Join-Path $root 'state.enc'
        Log 'Packing the staged profile and settings...'
        Invoke-Exe tar @('-cf', $tar, '-C', $stage, '.')
        Invoke-Exe zstd @('-q', '-f', '-T0', '-3', $tar, '-o', $zst)
        Invoke-Exe openssl @('enc', '-aes-256-cbc', '-pbkdf2', '-iter', '200000', '-salt',
            '-pass', 'env:STATE_PASSPHRASE', '-in', $zst, '-out', $encrypted)
        $chunks = @(Split-EncryptedFile $encrypted (Join-Path $output "state-$timestamp.enc.") $output)
        $manifestChunks = @($chunks | ForEach-Object {
            @{
                name = $_.Name
                size = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                hmac = Get-ChunkHmac $_.FullName
            }
        })
        $manifest = Join-Path $output "state-$timestamp.done.json"
        @{
            version = 2
            timestamp = $timestamp
            encryptedSize = (Get-Item -LiteralPath $encrypted).Length
            chunks = $manifestChunks
        } | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $manifest -Encoding utf8

        Ensure-Release
        $uploads = @($chunks.FullName) + $manifest
        # Chunks go first; the completion manifest is uploaded separately and last.
        Invoke-Exe gh (@('release', 'upload', $script:Tag, '-R', $script:Repo, '--clobber') + $chunks.FullName)
        Invoke-Exe gh @('release', 'upload', $script:Tag, '-R', $script:Repo, '--clobber', $manifest)
        $assets = @(Get-ReleaseAssets)
        foreach ($file in $uploads) {
            $item = Get-Item -LiteralPath $file
            $remote = @($assets | Where-Object name -eq $item.Name)
            if ($remote.Count -ne 1 -or [long]$remote[0].size -ne $item.Length) {
                throw "Upload verification failed for $($item.Name)"
            }
        }
        [IO.File]::WriteAllText($script:FingerprintFile, $fingerprint)

        # Reuse the successful listing above. A second transient empty listing
        # must never turn into permission to delete previous good snapshots.
        $keep = @($assets | ForEach-Object {
            if ($_.name -match '^state-(\d+)\.done\.json$') { $Matches[1] }
        } | Sort-Object -Descending -Unique | Select-Object -First $script:Keep)
        if ($keep -notcontains [string]$timestamp) {
            throw 'Retention refused: the newly verified checkpoint is missing from the keep list.'
        }
        foreach ($asset in $assets) {
            if ($asset.name -match '^state-(\d+)\.' -and $keep -notcontains $Matches[1]) {
                & gh release delete-asset $script:Tag $asset.name -R $script:Repo -y *> $null
            }
        }
        $sizeMiB = [Math]::Round((Get-Item -LiteralPath $encrypted).Length / 1MB, 1)
        Log "SAVE SUCCESS: checkpoint $timestamp verified ($($chunks.Count) encrypted chunks, $sizeMiB MiB)."
    } finally {
        if ($root -and (Test-Path -LiteralPath $root)) {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Restore-Packages([string]$Packages) {
    if ($env:STATE_SKIP_PACKAGES -eq '1') {
        Log 'Package restore skipped by STATE_SKIP_PACKAGES=1.'
        return
    }
    $winget = Join-Path $Packages 'winget.json'
    if ((Test-Path -LiteralPath $winget) -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log 'Restoring missing winget packages; installed packages are not upgraded.'
        & winget import --import-file $winget --ignore-unavailable --no-upgrade `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { Log 'WARNING: some winget packages could not be restored.' }
    }
    $choco = Join-Path $Packages 'choco.txt'
    if ((Test-Path -LiteralPath $choco) -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        foreach ($line in [IO.File]::ReadLines($choco)) {
            $parts = $line -split '\|'
            $name = $parts[0].Trim()
            if (-not $name) { continue }
            $installed = & choco list --local-only --exact $name --limit-output 2>$null
            if ($LASTEXITCODE -ne 0 -or -not ($installed | Where-Object { ($_ -split '\|')[0] -eq $name })) {
                $version = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                $arguments = @('install', $name, '-y', '--no-progress')
                if ($version) { $arguments += @('--version', $version) }
                & choco @arguments
                if ($LASTEXITCODE -ne 0) { Log "WARNING: Chocolatey package $name could not be restored." }
            }
        }
    }
    $pip = Join-Path $Packages 'pip-user.txt'
    if ((Test-Path -LiteralPath $pip) -and (Get-Item -LiteralPath $pip).Length -gt 0 -and
        (Get-Command python -ErrorAction SilentlyContinue)) {
        $installedJson = & python -m pip list --format=json 2>$null | Out-String
        $installedNames = @{}
        try {
            foreach ($package in ($installedJson | ConvertFrom-Json)) {
                $normalized = ($package.name.ToLowerInvariant() -replace '[_.]', '-')
                $installedNames[$normalized] = $true
            }
        } catch {
            Log 'WARNING: installed Python packages could not be enumerated; pip restore skipped.'
            $installedNames = $null
        }
        if ($null -ne $installedNames) {
            foreach ($requirement in [IO.File]::ReadLines($pip)) {
                $line = $requirement.Trim()
                if (-not $line -or $line.StartsWith('#')) { continue }
                $match = [Text.RegularExpressions.Regex]::Match($line, '^([A-Za-z0-9_.-]+)(==|@)')
                if (-not $match.Success) {
                    Log "WARNING: unsupported pip requirement skipped: $line"
                    continue
                }
                $name = $match.Groups[1].Value.ToLowerInvariant() -replace '[_.]', '-'
                if (-not $installedNames.ContainsKey($name)) {
                    & python -m pip install --user $line
                    if ($LASTEXITCODE -ne 0) { Log "WARNING: user Python package $name could not be restored." }
                    else { $installedNames[$name] = $true }
                }
            }
        }
    }
    $npm = Join-Path $Packages 'npm-global.json'
    if ((Test-Path -LiteralPath $npm) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
        try {
            $saved = Get-Content -LiteralPath $npm -Raw | ConvertFrom-Json
            $currentJson = & npm list -g --depth=0 --json 2>$null | Out-String
            $current = $currentJson | ConvertFrom-Json
            foreach ($property in $saved.dependencies.PSObject.Properties) {
                if (-not $current.dependencies.PSObject.Properties[$property.Name]) {
                    $version = $property.Value.version
                    $spec = if ($version) { "$($property.Name)@$version" } else { $property.Name }
                    & npm install -g $spec
                    if ($LASTEXITCODE -ne 0) { Log "WARNING: npm package $($property.Name) could not be restored." }
                }
            }
        } catch {
            Log "WARNING: npm package metadata could not be restored: $($_.Exception.Message)"
        }
    }
}

function Restore-State([switch]$VerifyOnly) {
    Initialize-State
    $stamps = @(Get-SnapshotStamps)
    if ($stamps.Count -eq 0) {
        if ($VerifyOnly) { throw 'No checkpoint exists.' }
        New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
        [IO.File]::WriteAllText($script:RestoreMarker, [DateTimeOffset]::UtcNow.ToString('o'))
        Log 'No previous checkpoint found; this run initialized a new persistent state.'
        return
    }

    foreach ($timestamp in $stamps) {
        $root = Join-Path $script:WorkRoot "restore-$timestamp"
        Reset-WorkPath $root
        $download = Join-Path $root 'download'
        $stage = Join-Path $root 'stage'
        New-Item -ItemType Directory -Path $download, $stage -Force | Out-Null
        $validated = $false
        try {
            Log "Trying checkpoint $timestamp..."
            Invoke-Exe gh @('release', 'download', $script:Tag, '-R', $script:Repo, '-D', $download,
                '--pattern', "state-$timestamp.enc.*", '--pattern', "state-$timestamp.done.json")
            $manifestPath = Join-Path $download "state-$timestamp.done.json"
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $chunkPaths = @()
            foreach ($chunk in $manifest.chunks) {
                $path = Join-Path $download $chunk.name
                if (-not (Test-Path -LiteralPath $path)) { throw "Missing chunk $($chunk.name)" }
                $item = Get-Item -LiteralPath $path
                if ($item.Length -ne [long]$chunk.size) { throw "Size mismatch for $($chunk.name)" }
                $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actual -ne $chunk.sha256) { throw "SHA-256 mismatch for $($chunk.name)" }
                if ([int]$manifest.version -ge 2) {
                    if (-not $chunk.hmac) { throw "Missing HMAC for $($chunk.name)" }
                    $actualHmac = Get-ChunkHmac $path
                    if ($actualHmac -ne $chunk.hmac) { throw "HMAC mismatch for $($chunk.name)" }
                } else {
                    Log 'Legacy checkpoint without HMAC; the final save will upgrade it to format 2.'
                }
                $chunkPaths += $path
            }
            $encrypted = Join-Path $root 'state.enc'
            $zst = Join-Path $root 'state.tar.zst'
            $tar = Join-Path $root 'state.tar'
            Join-EncryptedChunks $encrypted $chunkPaths
            Invoke-Exe openssl @('enc', '-d', '-aes-256-cbc', '-pbkdf2', '-iter', '200000',
                '-pass', 'env:STATE_PASSPHRASE', '-in', $encrypted, '-out', $zst)
            Invoke-Exe zstd @('-q', '-d', '-f', $zst, '-o', $tar)
            Invoke-Exe tar @('-xf', $tar, '-C', $stage)
            if (-not (Test-Path -LiteralPath (Join-Path $stage 'Metadata\snapshot.json'))) {
                throw 'Checkpoint metadata is missing.'
            }
            if (-not (Test-Path -LiteralPath (Join-Path $stage 'Profile'))) {
                throw 'Checkpoint profile is missing.'
            }
            $validated = $true
            Log "Checkpoint $timestamp passed SHA-256, decryption and archive validation."
            if ($VerifyOnly) { return }

            # No /MIR: restore never deletes files created by the new runner image.
            Copy-ProfileFromSource (Join-Path $stage 'Profile') $script:ProfileRoot -ForRestore
            $canarySource = Join-Path $stage 'Profile\Desktop\OpenBot.lnk'
            if (Test-Path -LiteralPath $canarySource) {
                $canaryDestination = Join-Path $script:ProfileRoot 'Desktop\OpenBot.lnk'
                if (-not (Test-Path -LiteralPath $canaryDestination)) {
                    throw 'Restore canary failed: Desktop\OpenBot.lnk did not reach the live profile.'
                }
                Log 'RESTORE CANARY: Desktop\OpenBot.lnk verified in the live profile.'
            }
            $hkcu = Join-Path $stage 'Metadata\Registry\HKCU.reg'
            if (Test-Path -LiteralPath $hkcu) {
                & reg import $hkcu
                if ($LASTEXITCODE -ne 0) {
                    # A stock HKCU export can contain protected keys owned by
                    # Windows. Reg imports the accessible keys before reporting
                    # the protected one; do not discard the whole restored profile.
                    Log 'WARNING: some protected HKCU keys could not be imported (details above).'
                }
            }
            Restore-Packages (Join-Path $stage 'Metadata\Packages')
            $openbot = Join-Path $env:LOCALAPPDATA 'Programs\OpenBot\OpenBot.exe'
            if (Test-Path -LiteralPath $openbot) {
                $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
                New-Item -Path $runKey -Force | Out-Null
                New-ItemProperty -Path $runKey -Name OpenBot -Value ('"{0}"' -f $openbot) -PropertyType String -Force | Out-Null
            }
            [IO.File]::WriteAllText($script:RestoreMarker, [DateTimeOffset]::UtcNow.ToString('o'))
            Log "RESTORE SUCCESS: checkpoint $timestamp applied without deleting new runner files."
            return
        } catch {
            Log "Checkpoint $timestamp could not be restored: $($_.Exception.Message)"
            # Once a checkpoint has been applied, never fall through and apply
            # an older one over the same profile.
            if ($validated) { throw }
        } finally {
            if (Test-Path -LiteralPath $root) {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    throw 'No complete checkpoint could be restored. Refusing to overwrite the saved state.'
}

function Hold-State {
    Initialize-State
    if (-not (Test-Path -LiteralPath $script:RestoreMarker)) {
        throw 'Restore must run before the session hold loop.'
    }
    # Never let a long restore consume the final-save budget. The hard job cap
    # is 360 minutes; stop the hold by minute 330 at the latest, leaving 20
    # minutes for final upload and another 10 for cleanup/post steps.
    $deadline = [Math]::Min(
        $script:JobStart + $script:SessionSeconds,
        $script:JobStart + 19800
    )
    $lastSave = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Log "Autosave every $($script:SaveEvery / 60) minutes; final checkpoint at $([DateTimeOffset]::FromUnixTimeSeconds($deadline).ToString('u'))."
    while ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -lt $deadline) {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $saveNow = Join-Path $script:ProfileRoot '.save-now'
        if ((Test-Path -LiteralPath $saveNow) -or ($now - $lastSave -ge $script:SaveEvery)) {
            Remove-Item -LiteralPath $saveNow -Force -ErrorAction SilentlyContinue
            try {
                Save-State
            } catch {
                Log "AUTOSAVE FAILED: $($_.Exception.Message); the previous complete checkpoint remains intact."
            }
            $lastSave = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        }
        $remaining = $deadline - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Start-Sleep -Seconds ([Math]::Max(1, [Math]::Min(15, $remaining)))
    }
    Save-State -Force
    if ($env:GITHUB_OUTPUT) {
        'saved=true' | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
        'chain=true' | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }
    Log 'Final checkpoint complete; this session can end and the next run can start.'
}

function Show-Status {
    Initialize-State
    $stamps = @(Get-SnapshotStamps)
    if ($stamps.Count -eq 0) {
        Log 'No checkpoints found.'
        return
    }
    foreach ($stamp in $stamps) {
        $asset = Get-ReleaseAssets | Where-Object name -eq "state-$stamp.done.json"
        Log "checkpoint=$stamp manifestBytes=$($asset.size)"
    }
}

New-Item -ItemType Directory -Path $script:WorkRoot -Force | Out-Null
switch ($Command) {
    'restore' { Restore-State }
    'verify' { Restore-State -VerifyOnly }
    'save' { Save-State }
    'hold' { Hold-State }
    'final' {
        Save-State -Force
        if ($env:GITHUB_OUTPUT) {
            'saved=true' | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
            'chain=true' | Out-File -LiteralPath $env:GITHUB_OUTPUT -Append -Encoding utf8
        }
    }
    'status' { Show-Status }
}
