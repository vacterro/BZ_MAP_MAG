[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $Apply,
    [ValidateRange(0, 5)] [int] $Keep = 0
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$root = Join-Path $repo 'build'
if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
$build = Get-Item -LiteralPath $root -Force
if ($build.FullName -ne $root -or ($build.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'The build directory must be local to this workspace.'
}

function Get-BuildTree([string] $Directory) {
    $folders = [System.Collections.Generic.Stack[string]]::new()
    $folders.Push($Directory)
    while ($folders.Count -gt 0) {
        $parent = $folders.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $parent -Force) {
            $item
            if ($item.PSIsContainer -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $folders.Push($item.FullName)
            }
        }
    }
}

$known = Get-ChildItem -LiteralPath $root -Directory -Force |
    Where-Object {
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        $_.Name -match '^(asset-test|bzn-185|bzn-probe|BZMAG|desktop|flat|path-profiles|sdk|test|ui-bridge)-[0-9a-f]{32}$'
    }
$expired = foreach ($group in $known | Group-Object { $_.Name -replace '-[0-9a-f]{32}$', '' }) {
    $ordered = $group.Group | Sort-Object LastWriteTimeUtc -Descending
    if ($group.Name -in 'BZMAG','bzn-185','sdk' -or $Keep -eq 0) { $ordered }
    else { $ordered | Select-Object -Skip $Keep }
}
$livePaths = @(Get-Process | ForEach-Object Path | Where-Object { $_ })
$liveTools = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%' OR Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
    ForEach-Object CommandLine | Where-Object { $_ })
$removedBytes = 0L
foreach ($folder in $expired) {
    $checked = Get-Item -LiteralPath $folder.FullName -Force
    if ($checked.Parent.FullName -ne $root -or ($checked.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Could not verify generated folder $($folder.FullName)."
    }
    $prefix = $checked.FullName + [IO.Path]::DirectorySeparatorChar
    if (@($livePaths | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count -or
        @($liveTools | Where-Object { $_.IndexOf($prefix, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) {
        Write-Warning "A process is using $($folder.Name)."
        continue
    }
    $entries = @(Get-BuildTree $checked.FullName)
    $bytes = [long](($entries | Where-Object { -not $_.PSIsContainer -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | Measure-Object Length -Sum).Sum)
    if ($Apply -and $PSCmdlet.ShouldProcess($checked.FullName, 'Remove generated build artifacts')) {
        foreach ($link in $entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
            # Unlink directory junctions without opening or recursing into their targets.
            if ($link.PSIsContainer) { [IO.Directory]::Delete($link.FullName, $false) }
            else { [IO.File]::Delete($link.FullName) }
        }
        if ((Get-BuildTree $checked.FullName | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | Measure-Object).Count) {
            throw "A link appeared during cleanup of $($folder.Name)."
        }
        try {
            Remove-Item -LiteralPath $checked.FullName -Recurse -Force
            $removedBytes += $bytes
        } catch {
            Write-Warning "Could not finish cleanup of $($folder.Name): $($_.Exception.Message)"
        }
    }
    [pscustomobject]@{ Artifact = $folder.Name; MiB = [Math]::Round($bytes / 1MB, 2); Present = Test-Path -LiteralPath $folder.FullName }
}
if ($Apply) { Write-Host ('Removed {0:N2} MiB of generated files.' -f ($removedBytes / 1MB)) }
