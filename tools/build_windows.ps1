param(
    [string]$GodotPath = 'C:/Program Files/Godot/Godot.exe',
    [string]$PythonPath = 'python',
    [switch]$PackOnly,
    [ValidatePattern('^$|^[0-9]+\.[0-9]+\.[0-9]+$')][string]$VersionedOutput = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot ('builds/windows' + $(if ($VersionedOutput) { '-' + $VersionedOutput } else { '' }))
$presetText = Get-Content -LiteralPath (Join-Path $projectRoot 'export_presets.cfg') -Raw -Encoding UTF8
if ($VersionedOutput -and [regex]::Match($presetText, '(?m)^application/file_version="([^"]+)"').Groups[1].Value -ne ($VersionedOutput + '.0')) {
    throw 'Versioned output must match the Windows preset.'
}
& $PythonPath (Join-Path $PSScriptRoot 'validate_product.py')
if ($LASTEXITCODE -ne 0) { throw 'Product dependency validation failed.' }
New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null
$logRoot = Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$executable = Join-Path $buildRoot '积木战争.exe'
$exportMode = '--export-release'
$exportTarget = $executable
if ($PackOnly) {
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Pack-only export requires an existing launcher.' }
    $version = [regex]::Match($presetText, '(?m)^application/file_version="([^"]+)"').Groups[1].Value
    if ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($executable).FileVersion -ne $version) { throw 'Launcher version differs; run a full export.' }
    $exportMode = '--export-pack'
    $exportTarget = Join-Path $buildRoot '积木战争.pck'
}
function Invoke-OwnedGodot([string[]]$EngineArgs, [int]$TimeoutSeconds = 300) {
    $owned = Start-Process -FilePath $GodotPath -ArgumentList $EngineArgs -WindowStyle Hidden -PassThru
    try {
        if (-not $owned.WaitForExit($TimeoutSeconds * 1000)) { throw 'Godot validation timed out.' }
        if ($owned.ExitCode -ne 0) { throw "Godot failed with exit code $($owned.ExitCode)." }
    } finally {
        if (-not $owned.HasExited) { Stop-Process -Id $owned.Id -Force }
        $owned.Dispose()
    }
}
$exportLog = Join-Path $logRoot 'windows-export.engine.log'
Invoke-OwnedGodot @('--headless', '--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $exportLog + '"'), $exportMode, '"Windows Desktop"', ('"' + $exportTarget + '"'))
if (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Export log contains errors.' }
# Run all six maps from the exported PCK, then release audio and return home.
$smokeLog = Join-Path $logRoot 'windows-package.engine.log'
Invoke-OwnedGodot @('--headless', '--main-pack', ('"' + (Join-Path $buildRoot '积木战争.pck') + '"'), '--log-file', ('"' + $smokeLog + '"'), '--script', ('"' + (Join-Path $projectRoot 'tests/product_release_test.gd') + '"')) 120
if (Select-String -LiteralPath $smokeLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Packaged startup failed.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/windows-readme.txt') -Destination (Join-Path $buildRoot 'START_HERE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/ui/medieval/fonts/OFL.txt') -Destination (Join-Path $buildRoot 'FONT_LICENSE.txt') -Force
$archive = Join-Path $projectRoot ('builds/积木战争-' + $(if ($VersionedOutput) { $VersionedOutput + '-' } else { '' }) + 'Windows-x64.zip')
$deliverables = @('积木战争.exe', '积木战争.pck', 'START_HERE.txt', 'FONT_LICENSE.txt') | ForEach-Object { Join-Path $buildRoot $_ }
Compress-Archive -LiteralPath $deliverables -DestinationPath $archive -Force
Get-Item -LiteralPath $executable, $archive | Select-Object FullName, Length
