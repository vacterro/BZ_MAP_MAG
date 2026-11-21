[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$brave = Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'
if (-not (Test-Path -LiteralPath $brave -PathType Leaf)) { throw "Missing fixture: $brave" }
$scratch = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ('bzmag-autosave-' + [guid]::NewGuid().ToString('N')))).FullName
$log = Join-Path $scratch 'godot.log'
$arguments = "--headless --path `"$app`" --log-file `"$log`" --script res://tests/autosave_store.gd -- `"$brave`" `"$scratch`""
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
$record = New-BzmagRunRecord $repo $scratch $process
if (-not $process.WaitForExit(240000)) {
    $process.Kill()
    if ($process.WaitForExit(10000)) { Complete-BzmagRunRecord $record $log $false }
    throw "Godot autosave test timed out. See $log"
}
Write-Output $scratch
$lines = @(Get-Content -LiteralPath $log)
$lines | Select-Object -First 60 | Write-Output
# The failure injection intentionally makes the engine print two expected
# error lines while catching them: the corrupt staged record (Parse JSON
# failed) and the unusable autosave root (Could not create directory).
# SCRIPT ERROR would mean a code defect, and FAILURES: 0 is the acceptance.
$passed = $process.ExitCode -eq 0 -and ($lines -match 'SCRIPT ERROR').Count -eq 0 -and $lines -contains 'FAILURES: 0'
Complete-BzmagRunRecord $record $log $passed
if (-not $passed) {
    throw "Autosave store failure-injection test failed. See $log"
}
