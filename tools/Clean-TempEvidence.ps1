[CmdletBinding()]
param(
    [string] $TempRoot = [IO.Path]::GetTempPath(),
    [ValidateRange(0, 5)] [int] $Keep = 1,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')
$workspace = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$parent = Get-Item -LiteralPath $TempRoot -Force -ErrorAction SilentlyContinue
if (-not $parent -or -not $parent.PSIsContainer) { return }
if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Temp evidence root must be a local directory.' }
$root = $parent.FullName
$suite = '^(bzmag-terrain|bzmag-layout|bzmag-autosave)-[a-f0-9]{32}$'
$probe = '-probe|^water-[a-f0-9-]+$|^bzm-[a-f0-9]{32}$'
$evidence = @(Get-Content -LiteralPath (Join-Path $workspace 'docs/EVIDENCE.md') -ErrorAction SilentlyContinue)
$state = Get-Content -LiteralPath (Join-Path $workspace '.saipen/STATE.md') -Raw -ErrorAction SilentlyContinue

function Test-BzmagRecordedLog($Entry) {
    $hash = [string]$Entry.Record.log_sha256
    if ($hash -notmatch '^[a-f0-9]{64}$' -or $Entry.Record.verdict -notin 'PASS','FAIL') { return $false }
    $name = [regex]::Escape($Entry.Folder.Name)
    if (-not ($evidence | Where-Object { $_ -match $name -and $_ -match $hash } | Select-Object -First 1)) { return $false }
    $log = Get-Item -LiteralPath (Join-Path $Entry.Folder.FullName 'godot.log') -Force -ErrorAction SilentlyContinue
    return $log -and -not $log.PSIsContainer -and -not ($log.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        (Get-BzmagFileSha256 $log.FullName) -eq $hash
}

function Test-BzmagRunInUse([string] $Run) {
    if ($state -and $state.Contains((Split-Path -Leaf $Run))) { return $true }
    foreach ($process in Get-CimInstance Win32_Process -ErrorAction Stop) {
        if ((Test-BzmagPathReference $process.ExecutablePath $Run) -or
            (Test-BzmagPathReference $process.CommandLine $Run)) { return $true }
    }
    return $false
}

function Get-BzmagPlainTreeSize([string] $Path) {
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Path)
    $size = 0L
    while ($pending.Count) {
        foreach ($entry in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { return -1L }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
            else { $size += $entry.Length }
        }
    }
    return $size
}

$owned = foreach ($folder in Get-ChildItem -LiteralPath $root -Directory -Force) {
    $group = if ($folder.Name -match $suite) { $Matches[1] } elseif ($folder.Name -match $probe) { 'probe' }
    if (-not $group) { continue }
    $record = Read-BzmagRunRecord $folder $workspace
    if (-not $record) {
        Write-Host "KEEP $($folder.Name) (unverified ownership)"
        continue
    }
    [pscustomobject]@{ Folder = $folder; Record = $record; Group = $group }
}

$removed = 0
$bytes = 0L
foreach ($group in $owned | Group-Object Group) {
    $ordered = @($group.Group | Sort-Object { $_.Folder.LastWriteTimeUtc } -Descending)
    $protected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($group.Name -ne 'probe') {
        foreach ($verdict in 'PASS','FAIL') {
            $newest = $ordered | Where-Object { $_.Record.verdict -eq $verdict } | Select-Object -First 1
            if ($newest) { [void]$protected.Add($newest.Folder.Name) }
        }
        if ($Keep -gt 0) {
            foreach ($extra in $ordered | Where-Object { -not $protected.Contains($_.Folder.Name) } | Select-Object -First $Keep) {
                [void]$protected.Add($extra.Folder.Name)
            }
        }
    }
    foreach ($entry in $ordered) {
        $name = $entry.Folder.Name
        if ($protected.Contains($name) -or ($group.Name -eq 'probe' -and $entry.Folder.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddHours(-1))) {
            Write-Host "KEEP $name (retention)"
            continue
        }
        if (-not (Test-BzmagRecordedLog $entry)) {
            Write-Host "KEEP $name (incomplete or unrecorded evidence)"
            continue
        }
        $path = $entry.Folder.FullName
        if (Test-BzmagRunInUse $path) {
            Write-Host "KEEP $name (live reference)"
            continue
        }
        $confirm = Get-Item -LiteralPath $path -Force
        $current = Read-BzmagRunRecord $confirm $workspace
        if ($confirm.Parent.FullName -ne $root -or -not $current -or
            $current.log_sha256 -ne $entry.Record.log_sha256 -or $current.verdict -ne $entry.Record.verdict) {
            throw "Could not reverify ownership of $path."
        }
        $size = Get-BzmagPlainTreeSize $path
        if ($size -lt 0) {
            Write-Host "KEEP $name (contains a link)"
            continue
        }
        if ($Apply) {
            Remove-Item -LiteralPath $confirm.FullName -Recurse -Force
            $removed++
            $bytes += $size
            Write-Host "REMOVED $name"
        } else {
            Write-Host "REMOVE $name (dry run)"
        }
    }
}
if ($Apply) { Write-Host ("Removed {0} folder(s), freed {1:N2} MiB." -f $removed, ($bytes / 1MB)) }
