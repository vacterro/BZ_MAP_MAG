[CmdletBinding()]
param(
    [string] $Root,
    [string] $TempRoot = [IO.Path]::GetTempPath(),
    [string[]] $RunToken,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$workspace = (Resolve-Path -LiteralPath $Root).Path
if ($Apply -and -not $RunToken) { throw 'Pass the private -RunToken for each workflow child you intend to stop.' }

function Get-BzmagOwnedProcess($Record) {
    $childId = 0
    if (-not [int]::TryParse([string]$Record.process_id, [ref]$childId) -or
        $childId -le 0 -or $childId -eq $PID -or -not $Record.started -or -not $Record.executable) {
        return
    }
    $live = Get-CimInstance Win32_Process -Filter "ProcessId = $childId" -ErrorAction Stop
    if (-not $live -or $live.ExecutablePath -ne $Record.executable -or
        -not $live.CommandLine -or
        -not (Test-BzmagPathReference $live.CommandLine $Record.run)) {
        return
    }
    # Suite runners use an external Godot executable with --path in this
    # workspace. Native Playtests use an executable in their private clone.
    if (-not (Test-BzmagPathReference $live.CommandLine $workspace)) {
        $runtime = Join-Path $Record.run 'game\battlezone2.exe'
        if ($live.ExecutablePath -ne $runtime -or -not (Test-BzmagPathReference $runtime $workspace)) { return }
    }
    $target = Get-Process -Id $childId -ErrorAction SilentlyContinue
    try {
        if ($target -and -not $target.HasExited -and $target.Path -eq $Record.executable -and
            $target.StartTime.ToFileTimeUtc().ToString() -ceq $Record.started) {
            return $target
        }
    } catch [InvalidOperationException] { }
}

$directories = @(
    @{ Path = Join-Path $workspace 'build'; Pattern = '^BZMAG-[a-f0-9]{32}$' }
    @{ Path = $TempRoot; Pattern = '^bzmag-(terrain|layout|autosave)-[a-f0-9]{32}$' }
)
$count = 0
foreach ($group in $directories) {
    $parent = Get-Item -LiteralPath $group.Path -Force -ErrorAction SilentlyContinue
    if (-not $parent -or -not $parent.PSIsContainer -or
        ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    foreach ($folder in Get-ChildItem -LiteralPath $parent.FullName -Directory -Force) {
        if ($folder.Name -notmatch $group.Pattern -or ($RunToken -and $folder.Name -notin $RunToken)) { continue }
        $record = Read-BzmagRunRecord $folder $workspace
        if (-not $record) { continue }
        $target = Get-BzmagOwnedProcess $record
        if (-not $target) { continue }
        $count++
        if ($Apply) {
            # Hold the process handle and rebind the record immediately before
            # stopping it. A process that reused the PID cannot pass this check.
            [void]$target.Handle
            $current = Read-BzmagRunRecord $folder $workspace
            $checked = if ($current) { Get-BzmagOwnedProcess $current }
            if (-not $checked -or $checked.Id -ne $target.Id -or $checked.StartTime -ne $target.StartTime) {
                Write-Warning "Ownership changed for $($folder.Name)."
                continue
            }
            $target.Kill()
            if (-not $target.WaitForExit(10000)) { throw "PID $($target.Id) is still exiting." }
            Write-Host "Stopped PID $($target.Id) in $($folder.Name)."
        } else {
            Write-Host "Owned PID $($target.Id) ($($target.ProcessName)) in $($folder.Name)."
        }
    }
}
if ($count -eq 0) { Write-Host 'No live processes matched workspace run records.' }
