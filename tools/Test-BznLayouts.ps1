[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$fixtures = @(
    (Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'),
    (Join-Path $repo 'map_references/blank_map1/duel_map_27_autosave_01.bzn'),
    (Join-Path $repo 'map_references/vsr_1197/vsrterrace2.bzn'),
    (Join-Path $repo 'map_references/vsr_1197/admemvolcvsr.bzn'),
    (Join-Path $repo 'map_references/stbolt_1200_text/STBolt.bzn')
)
foreach ($fixture in $fixtures) {
    if (-not (Test-Path -LiteralPath $fixture -PathType Leaf)) { throw "Missing layout fixture: $fixture" }
}
$scratch = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ('bzmag-layout-' + [guid]::NewGuid().ToString('N')))).FullName
$log = Join-Path $scratch 'godot.log'
$arguments = "--headless --path `"$app`" --log-file `"$log`" --script res://tests/bzn_layout_profiles.gd -- " + (($fixtures | ForEach-Object { '"{0}"' -f $_ }) -join ' ') + " `"$scratch`""
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
$record = New-BzmagRunRecord $repo $scratch $process
if (-not $process.WaitForExit(90000)) {
    $process.Kill()
    if ($process.WaitForExit(10000)) { Complete-BzmagRunRecord $record $log $false }
    throw "Godot layout test timed out. See $log"
}
Write-Output $scratch
$lines = @(Get-Content -LiteralPath $log)
$lines | Select-Object -First 60 | Write-Output
$passed = $process.ExitCode -eq 0 -and ($lines -match 'SCRIPT ERROR|^ERROR:').Count -eq 0 -and $lines -contains 'FAILURES: 0'
Complete-BzmagRunRecord $record $log $passed
if (-not $passed) {
    throw "BZN layout profile test failed. See $log"
}
