[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$brave = Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'
if (-not (Test-Path -LiteralPath $brave -PathType Leaf)) { throw "Missing fixture: $brave" }
$scratch = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ('bzmag-autosave-' + [guid]::NewGuid().ToString('N')))).FullName
$log = Join-Path $scratch 'godot.log'
$arguments = "--headless --path `"$app`" --log-file `"$log`" --script res://tests/autosave_store.gd -- `"$brave`" `"$scratch`""
$process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
if (-not $process.WaitForExit(120000)) {
    $process.Kill()
    throw "Godot autosave test timed out. See $log"
}
Write-Output $scratch
$lines = @(Get-Content -LiteralPath $log)
$lines | Select-Object -First 60 | Write-Output
# The failure injection intentionally makes the engine print two expected
# error lines while catching them: the corrupt staged record (Parse JSON
# failed) and the unusable autosave root (Could not create directory).
# SCRIPT ERROR would mean a code defect, and FAILURES: 0 is the acceptance.
if ($process.ExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR').Count -gt 0 -or -not ($lines -contains 'FAILURES: 0')) {
    throw "Autosave store failure-injection test failed. See $log"
}
