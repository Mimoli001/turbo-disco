#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
        $_.Name -match '^(devenv|MSBuild|VSIXInstaller|setup|vs_installer)(\.exe)?$'
    }
    if ($busy) { throw "Visual Studio processes are still running: $($busy.Name -join ', ')" }
    Write-Output '[prepare] Uninstalling Visual Studio Enterprise through its registered winget package...'
    & winget uninstall --id Microsoft.VisualStudio.Enterprise --exact --silent --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "Visual Studio winget uninstall exited with $LASTEXITCODE" }
    Write-Output '[prepare] Visual Studio Enterprise uninstalled.'
} else {
    Write-Output '[prepare] Visual Studio Enterprise is already absent.'
}

$free = Get-PSDrive C
Write-Output ("[prepare] C: free space is now {0:N2} GiB." -f ($free.Free / 1GB))
