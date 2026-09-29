param(
    [string]$GodotPath = '',
    [string]$PythonPath = 'python',
    [switch]$PackOnly,
    [ValidatePattern('^$|^[0-9]+\.[0-9]+\.[0-9]+$')][string]$VersionedOutput = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) { $GodotPath = Join-Path $projectRoot '.local/network/runtime/Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Prepare the verified Godot 4.7.2 runtime: python tools/deploy_block_war_relay.py --runtimes'
}
$runtimeVersion = & $GodotPath --version
if ($runtimeVersion -notmatch '^4\.7\.2\.') { throw 'This release requires Godot 4.7.2 for reliable DTLS teardown.' }
foreach ($template in @('windows_debug_x86_64.exe', 'windows_release_x86_64.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot ('.local/network/templates/' + $template)) -PathType Leaf)) {
        throw 'Prepare the verified export templates: python tools/deploy_block_war_relay.py --templates'
    }
}
& $PythonPath (Join-Path $PSScriptRoot 'build_network_manifest.py')
if ($LASTEXITCODE -ne 0) { throw 'Network content manifest generation failed.' }
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
# Refresh the native script-class and import registries before packing. A source
# removed since the last editor scan must not survive in the exported class cache.
$importLog = Join-Path $logRoot 'windows-import.engine.log'
Invoke-OwnedGodot @('--headless', '--editor', '--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $importLog + '"'), '--import')
if (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Native resource import contains errors.' }
# Godot's text-to-binary resource export cache can retain a removed exported
# property type even when the .tres text itself did not change. Rebuild that
# generated cache so old flat maps cannot reference deleted terrain scripts.
$exportCache = Join-Path $projectRoot '.godot/exported'
if (Test-Path -LiteralPath $exportCache) {
    $resolvedCache = (Resolve-Path -LiteralPath $exportCache).Path
    $expectedCache = [System.IO.Path]::GetFullPath((Join-Path $projectRoot '.godot/exported'))
    if ($resolvedCache -ne $expectedCache -or (Get-Item -LiteralPath $resolvedCache).LinkType) { throw 'Unexpected export cache location.' }
    Remove-Item -LiteralPath $resolvedCache -Recurse -Force
}
$exportLog = Join-Path $logRoot 'windows-export.engine.log'
Invoke-OwnedGodot @('--headless', '--path', ('"' + $projectRoot + '"'), '--log-file', ('"' + $exportLog + '"'), $exportMode, '"Windows Desktop"', ('"' + $exportTarget + '"'))
if (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Export log contains errors.' }
# Run every catalog map from the exported PCK, then release audio and return home.
$smokeLog = Join-Path $logRoot 'windows-package.engine.log'
$smokeRoot = Join-Path $logRoot 'package-isolated'
New-Item -ItemType Directory -Path $smokeRoot -Force | Out-Null
# An exported pack mounted from the source checkout can still resolve absent
# files from that checkout. Use an empty resource root to test the real product.
Invoke-OwnedGodot @('--headless', '--path', ('"' + $smokeRoot + '"'), '--main-pack', ('"' + (Join-Path $buildRoot '积木战争.pck') + '"'), '--log-file', ('"' + $smokeLog + '"'), '--script', ('"' + (Join-Path $projectRoot 'tests/product_release_test.gd') + '"')) 120
if (Select-String -LiteralPath $smokeLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) { throw 'Packaged startup failed.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/windows-readme.txt') -Destination (Join-Path $buildRoot 'START_HERE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'assets/ui/medieval/fonts/OFL.txt') -Destination (Join-Path $buildRoot 'FONT_LICENSE.txt') -Force
$licenseRoot = Join-Path $buildRoot 'licenses'
New-Item -ItemType Directory -Path $licenseRoot -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $projectRoot 'licenses') -Filter '*.txt' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $licenseRoot -Force
}
$archive = Join-Path $projectRoot ('builds/积木战争-' + $(if ($VersionedOutput) { $VersionedOutput + '-' } else { '' }) + 'Windows-x64.zip')
$deliverables = @('积木战争.exe', '积木战争.pck', 'START_HERE.txt', 'FONT_LICENSE.txt', 'licenses') | ForEach-Object { Join-Path $buildRoot $_ }
Compress-Archive -LiteralPath $deliverables -DestinationPath $archive -Force
Get-Item -LiteralPath $executable, $archive | Select-Object FullName, Length
