[CmdletBinding()]
param(
    [string] $TempRoot = 'V:\_TEMP_',
    [ValidateRange(0, 5)] [int] $Keep = 1,
    [switch] $Apply
)

# Prunes test evidence folders under the temp root that this workspace owns,
# with retention rules instead of broad wildcards:
#   * Suite groups (bzmag-terrain-, bzmag-layout-, bzmag-autosave-) are known
#     BZ_MAP_MAG runners by their name + 32-hex run id. Per group the newest
#     PASS and the newest FAIL are always kept (a failure diagnosis must never
#     be a deleted last copy) plus the -Keep newest runs overall.
#   * One-off probe/scratch folders (water-*, *-probe*, bzm-<guid>) are
#     removed only when their newest file is at least an hour old, nothing
#     references them and their evidence is recorded in docs/EVIDENCE.md.
# Live references are honored, dry-run is the default, and a repeated run is a
# no-op once everything eligible is gone.

$ErrorActionPreference = 'Stop'
$suitePattern = '^(bzmag-terrain|bzmag-layout|bzmag-autosave)-[0-9a-f]{32}$'
# Probe conventions this workspace generated. A generic '*-probe*' name is
# NOT ownership: other tooling names temp folders the same way, so those
# folders must still prove an internal workspace marker before removal.
$ownedProbeNames = '^water-[0-9a-f][0-9a-f-]*$','^bzm-[0-9a-f]{32}$','^(native-route|bzn-conv)-probe$'
function Test-ProbeOwned([System.IO.DirectoryInfo] $Folder) {
    if ($Folder.Name -match ($ownedProbeNames -join '|')) { return $true }
    $markers = Get-ChildItem -LiteralPath $Folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -lt 64KB } | Select-Object -First 200
    foreach ($file in $markers) {
        $name = $file.Name.ToLowerInvariant()
        if ($name -match '^(braveliltoaster|duel_map_27_autosave_01|vsrterrace2|admemvolcvsr|stbolt)\.[a-z0-9]+$') { return $true }
        if ($name -match '\.(log|txt|json|md|ps1|py|gd)$') {
            if (Select-String -LiteralPath $file.FullName -Pattern 'BZ_MAP_MAG|res://tests|bzmag-' -Quiet -ErrorAction SilentlyContinue) { return $true }
        }
    }
    return $false
}
if (-not (Test-Path -LiteralPath $TempRoot -PathType Container)) {
    Write-Host "Temp root $TempRoot does not exist; nothing to prune."
    return
}
$root = (Resolve-Path -LiteralPath $TempRoot).Path

$liveReferences = [System.Collections.Generic.List[string]]::new()
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
    foreach ($entry in @($_.ExecutablePath, $_.CommandLine)) {
        if (-not $entry) { continue }
        $index = $entry.IndexOf($root, [StringComparison]::OrdinalIgnoreCase)
        if ($index -ge 0) { $liveReferences.Add($entry.Substring($index)) }
    }
}
function Test-Referenced([string] $Folder) {
    $prefix = $Folder.TrimEnd('\') + '\'
    foreach ($path in $liveReferences) {
        if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-Verdict([string] $Folder) {
    # PASS/FAIL from the suite log; UNKNOWN means keep the folder.
    $log = Get-ChildItem -LiteralPath $Folder -Filter *.log -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $log) { return 'UNKNOWN' }
    $match = Select-String -LiteralPath $log.FullName -Pattern '^FAILURES: ([0-9]+)' |
        Select-Object -Last 1
    if (-not $match) { return 'UNKNOWN' }
    if ([int]$match.Matches[0].Groups[1].Value -eq 0) { return 'PASS' }
    return 'FAIL'
}

$folders = @(Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object {
    -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
})

$dispositions = [System.Collections.Generic.List[object]]::new()

function Add-Disposition([System.IO.DirectoryInfo] $Folder, [string] $Disposition) {
    $script:dispositions.Add([pscustomobject]@{
        Name = $Folder.Name
        Disposition = $Disposition
    }) | Out-Null
}

foreach ($prefix in 'bzmag-terrain-','bzmag-layout-','bzmag-autosave-') {
    $group = @($folders | Where-Object { $_.Name -match ('^' + $prefix + '[0-9a-f]{32}$') } |
        Sort-Object LastWriteTimeUtc -Descending)
    if (-not $group.Count) { continue }
    $retained = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($index in 0..([Math]::Min($Keep, $group.Count) - 1)) { [void]$retained.Add($group[$index].Name) }
    $newestPass = @($group | Where-Object { (Get-Verdict $_.FullName) -eq 'PASS' } | Select-Object -First 1)
    $newestFail = @($group | Where-Object { (Get-Verdict $_.FullName) -eq 'FAIL' } | Select-Object -First 1)
    foreach ($entry in ($newestPass + $newestFail)) { [void]$retained.Add($entry.Name) }
    foreach ($folder in $group) {
        if ($retained.Contains($folder.Name)) {
            Add-Disposition $folder ('KEEP newest-PASS/newest-FAIL/-Keep window ' + (Get-Verdict $folder.FullName))
        } elseif ((Get-Verdict $folder.FullName) -eq 'UNKNOWN') {
            # UNKNOWN is usually a killed or crashed run. Keep it while it is
            # fresh enough to still be an open diagnosis, prune once it is
            # more than a day old and its story is in docs/EVIDENCE.md.
            if ($folder.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddHours(-24)) {
                Add-Disposition $folder 'REMOVE unknown run older than a day'
            } else {
                Add-Disposition $folder 'KEEP unknown verdict'
            }
        } else {
            Add-Disposition $folder ('REMOVE older ' + (Get-Verdict $folder.FullName) + ' run')
        }
    }
}

foreach ($folder in $folders) {
    if ($folder.Name -match $suitePattern) { continue }
    # Foreign and unrelated folders never enter the tool's universe at all;
    # only probe-like names are considered, and even those must prove ownership.
    $candidate = ($folder.Name -match '-probe') -or ($folder.Name -match ($ownedProbeNames -join '|'))
    if (-not $candidate) { continue }
    if (-not (Test-ProbeOwned $folder)) {
        Add-Disposition $folder 'KEEP unverified ownership'
        continue
    }
    $newest = Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $newest) { Add-Disposition $folder 'REMOVE empty owned scratch folder' ; continue }
    if ($newest.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddHours(-1)) {
        Add-Disposition $folder 'KEEP written within the last hour'
    } else {
        Add-Disposition $folder 'REMOVE owned one-off probe over an hour old'
    }
}

if ($dispositions.Count -eq 0) {
    Write-Host "No workspace-owned folders under $TempRoot."
    return
}

$freedBytes = 0L
$removedCount = 0
foreach ($item in $dispositions) {
    $folder = Get-Item -LiteralPath (Join-Path $root $item.Name) -Force -ErrorAction SilentlyContinue
    if (-not $folder) { continue }
    $size = [long]((Get-ChildItem -LiteralPath $folder.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        Measure-Object Length -Sum).Sum)
    Write-Host ("{0,-7} {1,10:N2} MiB  {2}" -f $item.Disposition.Substring(0, [Math]::Min(7, $item.Disposition.Length)), ($size / 1MB), $item.Name)
    if (-not $item.Disposition.StartsWith('REMOVE')) { continue }
    if (-not $Apply) { continue }
    if (Test-Referenced $folder.FullName) {
        Write-Warning "        skipped $($item.Name): a live process references it."
        continue
    }
    $confirm = Get-Item -LiteralPath $folder.FullName -Force
    if ($confirm.Parent.FullName -ne $root -or
        ($confirm.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to remove a folder that moved or became a link: $($folder.FullName)"
    }
    try {
        Remove-Item -LiteralPath $confirm.FullName -Recurse -Force
        $freedBytes += $size
        $removedCount++
    } catch {
        Write-Warning "        could not remove $($item.Name): $($_.Exception.Message)"
    }
}
Write-Host ""
if (-not $Apply) {
    Write-Host "Dry run: re-run with -Apply to remove the listed folders once their evidence is recorded in docs/EVIDENCE.md."
} else {
    Write-Host ("Removed {0} folder(s), freed {1:N2} MiB." -f $removedCount, ($freedBytes / 1MB))
}
