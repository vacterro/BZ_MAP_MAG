[CmdletBinding()]
param(
    [string] $Root,
    [switch] $Apply
)

# Stop only processes this workspace owns. Ownership is proven by location:
# the executable runs from inside the repository, or a known tooling process
# (shells, python, dotnet, Godot, the cloned game) carries a repository path in
# its command line. Anything else — the user's own Battlezone session from the
# Steam folder, unrelated Godot projects, editors and browsers that merely
# mention a repo path — is never touched, and nothing is ever matched by name
# alone. This tool and its ancestors are excluded so the invoking shell
# survives. Dry-run by default; -Apply re-verifies each PID immediately before
# stopping and reports every result.

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = (Resolve-Path -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) '.')).Path }
$rootTrimmed = $Root.TrimEnd('\').TrimEnd('/')
$rootPrefix = $rootTrimmed + '\'
$rootSlash = $rootTrimmed + '/'
$toolingNames = @('powershell.exe','pwsh.exe','cmd.exe','python.exe','py.exe','dotnet.exe','msbuild.exe','cl.exe','bash.exe','sh.exe','battlezone2.exe')

function Test-ExeOwned([string] $Value) {
    if (-not $Value) { return $false }
    $trimmed = $Value.Trim('"')
    return ($trimmed.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $trimmed.StartsWith($rootSlash, [StringComparison]::OrdinalIgnoreCase))
}

function Test-CommandLineOwned([string] $ProcessName, [string] $CommandLine) {
    if (-not $CommandLine -or -not $ProcessName) { return $false }
    # A repository path anywhere in the command line, in either slash form and
    # with or without a trailing separator, so bare path arguments match too.
    $normalized = $CommandLine.Replace('/', '\')
    $references = ($normalized.IndexOf($rootTrimmed, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    if (-not $references) { return $false }
    $lower = $ProcessName.ToLowerInvariant()
    return ($lower -match '^godot') -or ($toolingNames -contains $lower)
}

# The PID chain that must survive regardless of matches.
$protected = [System.Collections.Generic.HashSet[int]]::new()
$cursor = $PID
while ($cursor -and $protected.Add($cursor)) {
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $cursor" -ErrorAction SilentlyContinue
    $cursor = if ($parent) { [int]$parent.ParentProcessId } else { 0 }
}

$candidates = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    -not $protected.Contains([int]$_.ProcessId) -and
    ((Test-ExeOwned $_.ExecutablePath) -or (Test-CommandLineOwned $_.Name $_.CommandLine))
})

if (-not $candidates.Count) {
    Write-Host "No workspace-owned processes are running."
    return
}

$report = foreach ($process in $candidates) {
    [pscustomobject]@{
        Id = $process.ProcessId
        Name = $process.Name
        StartedUtc = $process.CreationDate
        Evidence = if (Test-ExeOwned $process.ExecutablePath) { $process.ExecutablePath } else { $process.CommandLine }
    }
}
$report | Sort-Object Id | Format-Table -AutoSize | Out-String | Write-Host

if (-not $Apply) {
    Write-Host ("Dry run: {0} workspace-owned process(es) listed; none were stopped. Re-run with -Apply to stop them." -f $candidates.Count)
    return
}

$stopped = 0
foreach ($entry in $report) {
    try {
        $target = Get-Process -Id $entry.Id -ErrorAction Stop
        # Re-verify ownership immediately before stopping: PID reuse safety.
        $live = Get-CimInstance Win32_Process -Filter "ProcessId = $($entry.Id)" -ErrorAction SilentlyContinue
        if (-not $live -or -not ((Test-ExeOwned $live.ExecutablePath) -or (Test-CommandLineOwned $live.Name $live.CommandLine)) -or $protected.Contains([int]$entry.Id)) {
            Write-Warning "Process $($entry.Id) no longer qualifies as workspace-owned; skipped."
            continue
        }
        Stop-Process -Id $entry.Id -Force -ErrorAction Stop
        $stopped++
        Write-Host ("Stopped {0} {1} (started {2})." -f $entry.Id, $entry.Name, $entry.StartedUtc)
    } catch {
        Write-Warning ("Could not stop process {0}: {1}" -f $entry.Id, $_.Exception.Message)
    }
}
Write-Host ("Stopped {0} of {1} workspace-owned processes." -f $stopped, $candidates.Count)
if ($stopped -lt $candidates.Count) { exit 1 }
