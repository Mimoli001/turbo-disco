#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-BoundedProcess {
    # Runs a process with a heartbeat in the step log and a hard deadline.
    # A step that stays silent for tens of minutes looks hung and gets
    # cancelled by hand before it can ever finish.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][int]$TimeoutMinutes,
        [Parameter(Mandatory)][string]$Label
    )
    $started = Get-Date
    $deadline = $started.AddMinutes($TimeoutMinutes)
    Write-Output "[prepare] $Label started (deadline: $TimeoutMinutes minutes)."
    Write-Output "[prepare] Command: `"$FilePath`" $CommandLine"
    # The VS installer must be started from a directory other than its own.
    $proc = Start-Process -FilePath $FilePath -ArgumentList $CommandLine -WorkingDirectory $env:TEMP -PassThru -WindowStyle Hidden
    while (-not $proc.HasExited) {
        if ((Get-Date) -gt $deadline) {
            Write-Output "::warning::$Label exceeded its $TimeoutMinutes minute deadline; terminating it and moving on."
            try { $proc.Kill($true) | Out-Null } catch { Write-Output "[prepare] Process tree kill failed: $($_.Exception.Message)" }
            Start-Sleep -Seconds 5
            return @{ TimedOut = $true; ExitCode = $null }
        }
        Start-Sleep -Seconds 60
        if (-not $proc.HasExited) {
            Write-Output ("[prepare] {0} still running, elapsed {1:hh\:mm\:ss}." -f $Label, ((Get-Date) - $started))
        }
    }
    return @{ TimedOut = $false; ExitCode = $proc.ExitCode }
}

function Move-Toolchain([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Output "[prepare] Already moved: $Source"
        return
    }
    if (Test-Path -LiteralPath $Destination) {
        throw "Both tool paths exist; refusing to choose between them: $Source and $Destination"
    }
    $busy = Get-CimInstance Win32_Process | Where-Object {
        ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($Source, [StringComparison]::OrdinalIgnoreCase)) -or
        ($_.CommandLine -and $_.CommandLine.Contains($Source, [StringComparison]::OrdinalIgnoreCase))
    }
    if ($busy) {
        throw "A process is using $Source; move refused: $($busy.Name -join ', ')"
    }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Write-Output "[prepare] Moving $Source to $Destination..."
    & robocopy $Source $Destination /E /B /COPY:DAT /DCOPY:T /XJ /R:1 /W:1 /NP /NFL /NDL /NJH /NJS
    $code = $LASTEXITCODE
    if ($code -gt 3) { throw "Robocopy failed for $Source with code $code" }
    $sourceFiles = Get-ChildItem -LiteralPath $Source -Recurse -Force -File -ErrorAction SilentlyContinue
    $destinationFiles = Get-ChildItem -LiteralPath $Destination -Recurse -Force -File -ErrorAction SilentlyContinue
    $sourceBytes = ($sourceFiles | Measure-Object Length -Sum).Sum
    $destinationBytes = ($destinationFiles | Measure-Object Length -Sum).Sum
    if ($sourceFiles.Count -ne $destinationFiles.Count -or $sourceBytes -ne $destinationBytes) {
        throw "Toolchain verification failed for $Source"
    }
    Write-Output "[prepare] Copy verified ($($sourceFiles.Count) files, $sourceBytes bytes); removing the original..."
    Remove-Item -LiteralPath $Source -Recurse -Force
    Write-Output "[prepare] Moved $Source to $Destination ($sourceBytes bytes verified)."
}

function Update-PathReferences([string]$Source, [string]$Destination) {
    $env:PATH = $env:PATH.Replace($Source, $Destination)
    $targets = @(
        'HKCU:\Environment',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    )
    foreach ($target in $targets) {
        $item = Get-ItemProperty -LiteralPath $target -Name Path -ErrorAction SilentlyContinue
        if ($item -and $item.Path.Contains($Source, [StringComparison]::OrdinalIgnoreCase)) {
            Set-ItemProperty -LiteralPath $target -Name Path -Value $item.Path.Replace($Source, $Destination)
        }
    }
    if ($env:GITHUB_ENV) {
        "PATH=$env:PATH" | Out-File -LiteralPath $env:GITHUB_ENV -Append -Encoding utf8
    }
}

$moves = @(
    @{ Source = 'C:\Julia'; Destination = 'D:\DevTools\Julia' },
    @{ Source = 'C:\rtools45'; Destination = 'D:\DevTools\rtools45' },
    @{ Source = 'C:\Strawberry'; Destination = 'D:\DevTools\Strawberry' }
)
foreach ($move in $moves) {
    Move-Toolchain $move.Source $move.Destination
    Update-PathReferences $move.Source $move.Destination
}

$visualStudio = 'C:\Program Files\Microsoft Visual Studio\18\Enterprise'
if (Test-Path -LiteralPath $visualStudio) {
    $busy = Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^(devenv|MSBuild|VSIXInstaller|setup|vs_installer|InstallCleanup)(\.exe)?$'
    }
    if ($busy) { throw "Visual Studio processes are still running: $($busy.Name -join ', ')" }
    $installerDir = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer'
    $uninstaller = @('setup.exe', 'vs_installer.exe') |
        ForEach-Object { Join-Path $installerDir $_ } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if ($uninstaller) {
        # winget's Visual Studio wrapper is deliberately not used: with
        # --silent --disable-interactivity it can still surface a hidden
        # interactive prompt from the VS uninstaller and hang the run.
        # The native installer CLI with --quiet shows no UI at all.
        Write-Output '[prepare] Uninstalling Visual Studio Enterprise with the native installer (typically 10-25 minutes)...'
        $commandLine = 'uninstall --installPath "{0}" --quiet --norestart --force' -f $visualStudio
        $result = Invoke-BoundedProcess -FilePath $uninstaller -CommandLine $commandLine -TimeoutMinutes 30 -Label 'Visual Studio uninstall'
        if ($result.TimedOut) {
            $cleanup = Join-Path $installerDir 'InstallCleanup.exe'
            if (Test-Path -LiteralPath $cleanup) {
                Write-Output '[prepare] Falling back to the documented InstallCleanup.exe -f force removal...'
                Invoke-BoundedProcess -FilePath $cleanup -CommandLine '-f' -TimeoutMinutes 10 -Label 'InstallCleanup force removal' | Out-Null
            } else {
                Write-Output '::warning::Visual Studio uninstall timed out and InstallCleanup.exe is not available.'
            }
        } elseif ($result.ExitCode -notin 0, 1641, 3010) {
            Write-Output "::warning::Visual Studio uninstaller exited with code $($result.ExitCode); details are in the runner's %TEMP% dd_* setup logs."
        }
    } else {
        Write-Output '::warning::Visual Studio is present but its installer folder is missing; skipping removal because winget uninstall hangs on Visual Studio.'
    }
    if (Test-Path -LiteralPath $visualStudio) {
        Write-Output '::warning::Visual Studio is still installed; continuing so the session can start. C: keeps the Visual Studio footprint.'
    } else {
        Write-Output '[prepare] Visual Studio Enterprise removed.'
    }
} else {
    Write-Output '[prepare] Visual Studio Enterprise is already absent.'
}

$free = Get-PSDrive C
Write-Output ("[prepare] C: free space is now {0:N2} GiB." -f ($free.Free / 1GB))
