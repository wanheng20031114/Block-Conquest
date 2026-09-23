# Preview by default. Run with -Apply from a local PowerShell session to remove
# generated outputs. Keeps deployment credentials and every registered worktree.
# -IntermediatesOnly limits cleanup to review frames/logs, named one-off scripts,
# and tools Python bytecode; final GIF/MP4 files and the modeling environment stay.
[CmdletBinding()]
param([switch]$Apply, [switch]$IntermediatesOnly)

$ErrorActionPreference = 'Stop'
$taskWorkspace = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$taskLocal = (Resolve-Path -LiteralPath (Join-Path $taskWorkspace '.local')).Path
$taskArtifacts = (Resolve-Path -LiteralPath (Join-Path $taskWorkspace 'artifacts')).Path
foreach ($taskRoot in @($taskLocal, $taskArtifacts)) {
    if ([IO.Path]::GetDirectoryName($taskRoot) -ne $taskWorkspace) { throw 'Output root is outside this workspace.' }
    if ((Get-Item -LiteralPath $taskRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Output root is a link.' }
}

# Preserve the entire top-level directory containing a registered worktree,
# including its adjacent notes. Do not remove worktrees or discard changes.
$taskKeepLocal = @('network')
$taskWorktreeLines = & git -C $taskWorkspace -c core.quotepath=false worktree list --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect registered worktrees.' }
foreach ($taskLine in $taskWorktreeLines) {
    if ($taskLine.StartsWith('worktree ')) {
        $taskWorktree = [IO.Path]::GetFullPath($taskLine.Substring(9))
        if ($taskWorktree.StartsWith($taskLocal + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            $taskRelative = $taskWorktree.Substring($taskLocal.Length + 1)
            $taskKeepLocal += $taskRelative.Split([IO.Path]::DirectorySeparatorChar)[0]
        }
    }
}
$taskCandidates = @(Get-ChildItem -LiteralPath $taskLocal -Force | Where-Object { $_.Name -notin $taskKeepLocal -and $_.Name -ne '.gdignore' })
$taskNetwork = Join-Path $taskLocal 'network'
if (Test-Path -LiteralPath $taskNetwork) {
    if ((Get-Item -LiteralPath $taskNetwork -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Network directory is a link.' }
    $taskCandidates += @(Get-ChildItem -LiteralPath $taskNetwork -Force | Where-Object { $_.Name -notin @('relay-private.key', 'endpoint.json') })
}
$taskCandidates += @(Get-ChildItem -LiteralPath $taskArtifacts -Force | Where-Object { $_.Name -ne '.gdignore' })

$taskCache = Join-Path $taskWorkspace 'tools/__pycache__'
$taskTrackedIntermediatePaths = @()
if ($IntermediatesOnly) {
    $taskArtifactEntries = @(Get-ChildItem -LiteralPath $taskArtifacts -Force -Recurse)
    if (@($taskArtifactEntries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Linked artifact descendant.' }
    $taskCandidates = @($taskArtifactEntries | Where-Object { -not $_.PSIsContainer -and $_.Extension -in @('.png', '.log', '.txt') })
    $taskOneOffNames = @('house_four_capture.gd', 'refine_skill_layout.py', 'route_flow_audit.gd', 'skill_hud_capture.gd', 'update_war_ui.py', 'war_ui_capture.gd')
    foreach ($taskOneOffName in $taskOneOffNames) {
        $taskOneOffPath = Join-Path $taskLocal $taskOneOffName
        if (Test-Path -LiteralPath $taskOneOffPath -PathType Leaf) { $taskCandidates += Get-Item -LiteralPath $taskOneOffPath -Force }
    }
    if (Test-Path -LiteralPath $taskCache) {
        foreach ($taskCacheParent in @((Join-Path $taskWorkspace 'tools'), $taskCache)) {
            if ((Get-Item -LiteralPath $taskCacheParent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked cache path: $taskCacheParent" }
        }
        $taskCandidates += @(Get-ChildItem -LiteralPath $taskCache -File -Force -Filter '*.pyc')
    }
    $taskTrackedIntermediatePaths = @(& git -C $taskWorkspace -c core.quotepath=false ls-files -- artifacts .local tools/__pycache__)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked intermediate paths.' }
}

$taskTargets = @()
foreach ($taskItem in $taskCandidates) {
    $taskResolved = (Resolve-Path -LiteralPath $taskItem.FullName).Path
    $taskInside = $taskResolved.StartsWith($taskLocal + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $taskResolved.StartsWith($taskArtifacts + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or ($IntermediatesOnly -and $taskResolved.StartsWith($taskCache + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))
    if (-not $taskInside -or ($taskItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unsafe target: $taskResolved" }
    if ($IntermediatesOnly) {
        $taskRelativePath = $taskResolved.Substring($taskWorkspace.Length + 1).Replace('\', '/')
        if ($taskRelativePath -in $taskTrackedIntermediatePaths) { throw "Tracked file in intermediate cleanup: $taskRelativePath" }
        if ($taskResolved.StartsWith($taskLocal + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and $taskResolved.Substring($taskLocal.Length + 1).Split([IO.Path]::DirectorySeparatorChar)[0] -in $taskKeepLocal) { throw "Protected local path: $taskRelativePath" }
    }
    $taskEntries = @($taskItem)
    if ($taskItem.PSIsContainer) { $taskEntries += @(Get-ChildItem -LiteralPath $taskResolved -Force -Recurse) }
    if (@($taskEntries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw "Linked descendant: $taskResolved" }
    $taskFiles = @($taskEntries | Where-Object { -not $_.PSIsContainer })
    # An unexpected credential needs manual review, never implicit deletion.
    if (@($taskFiles | Where-Object { $_.Extension -in @('.key', '.pem', '.pfx', '.p12') -or $_.Name -eq '.env' }).Count) { throw "Credential-like file in cleanup target: $taskResolved" }
    $taskBytes = ($taskFiles | Measure-Object -Property Length -Sum).Sum
    $taskTargets += [pscustomobject]@{ Path = $taskResolved; Bytes = [long]$taskBytes; Files = $taskFiles.Count }
}

if ($IntermediatesOnly) {
    $taskTargets | Group-Object { [IO.Path]::GetDirectoryName($_.Path) } | Select-Object @{Name='Directory';Expression={$_.Name.Substring($taskWorkspace.Length + 1)}}, @{Name='MiB';Expression={[math]::Round(($_.Group | Measure-Object Bytes -Sum).Sum / 1MB, 2)}}, @{Name='Files';Expression={$_.Count}} | Format-Table -AutoSize
} else {
    $taskTargets | Sort-Object Bytes -Descending | Select-Object @{Name='RelativePath';Expression={$_.Path.Substring($taskWorkspace.Length + 1)}}, @{Name='MiB';Expression={[math]::Round($_.Bytes / 1MB, 2)}}, Files | Format-Table -AutoSize
}
$taskTotal = [long](($taskTargets | Measure-Object -Property Bytes -Sum).Sum)
Write-Output ('Eligible output size: {0:N3} GiB; {1} bytes' -f ($taskTotal / 1GB), $taskTotal)
Write-Output ('Protected local directories: ' + ($taskKeepLocal -join ', '))
Write-Output 'Protected network files: relay-private.key, endpoint.json; protected artifacts marker: .gdignore'
if ($IntermediatesOnly) { Write-Output 'Intermediates only: final GIF/MP4 files, tracked files and architecture-venv are retained.' }
if (-not $Apply) {
    Write-Output 'Preview only: no files were removed. -Apply performs the listed cleanup.'
    return
}

# The command-line check is conservative: do not delete an active experiment.
$taskProcesses = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine })
foreach ($taskTarget in $taskTargets) {
    foreach ($taskProcess in $taskProcesses) {
        $taskCommand = $taskProcess.CommandLine.Replace('/', '\')
        if ($taskCommand.IndexOf($taskTarget.Path, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "Process $($taskProcess.ProcessId) references $($taskTarget.Path). Stop that process before cleanup."
        }
    }
}
$taskRemovedBytes = [long]0
foreach ($taskTarget in $taskTargets) {
    if ($IntermediatesOnly) {
        Remove-Item -LiteralPath $taskTarget.Path -Force
    } else {
        Remove-Item -LiteralPath $taskTarget.Path -Recurse -Force
    }
    if (Test-Path -LiteralPath $taskTarget.Path) { throw "Target remains: $($taskTarget.Path)" }
    $taskRemovedBytes += $taskTarget.Bytes
}
$taskMarker = Join-Path $taskArtifacts '.gdignore'
if (-not (Test-Path -LiteralPath $taskMarker)) { [IO.File]::WriteAllText($taskMarker, "`n", [Text.UTF8Encoding]::new($false)) }
Write-Output ('Removed {0:N3} GiB of file contents ({1} bytes). Protected data retained.' -f ($taskRemovedBytes / 1GB), $taskRemovedBytes)
