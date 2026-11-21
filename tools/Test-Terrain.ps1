[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot,
    [switch] $WithGpu
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$brave = Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'
$blank = Join-Path $repo 'map_references/blank_map1/duel_map_27_autosave_01.bzn'
$scratch = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ('bzmag-terrain-' + [guid]::NewGuid().ToString('N')))).FullName
$log = Join-Path $scratch 'godot.log'
$mode = if ($WithGpu) { '--resolution 640x540' } else { '--headless' }
$arguments = "$mode --path `"$app`" --log-file `"$log`" --script res://tests/terrain_workflow.gd -- `"$brave`" `"$blank`" `"$scratch`""
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(90000)) {
    $process.Kill()
    throw "Godot test timed out. See $log"
}
Write-Output $scratch
$lines = @(Get-Content -LiteralPath $log)
$lines | Select-Object -First 100 | Write-Output
if ($process.ExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR|^ERROR:').Count -gt 0 -or -not ($lines -contains 'FAILURES: 0')) {
    throw "Terrain workflow failed. See $log"
}
# The layout capability test runs the registry against every verified BZN fixture.
& (Join-Path $PSScriptRoot 'Test-BznLayouts.ps1') -Godot $Godot
# The autosave failure-injection protocol proves the newest confirmed copy
# survives every simulated write, verify, publish, crash and prune failure.
& (Join-Path $PSScriptRoot 'Test-AutosaveStore.ps1') -Godot $Godot
