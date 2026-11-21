[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot,
    [Parameter(Mandatory)] [string] $Game,
    [switch] $WithGpu
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$assetFolder = Join-Path $repo 'build/object-preview'
$adapter = Join-Path $assetFolder 'mesh-preview.exe'
if (-not (Test-Path -LiteralPath $adapter -PathType Leaf)) { throw 'Compile the local VRV adapter with Build-ObjectPreview.ps1.' }
$app = Join-Path $repo 'app'
$map = Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'
$log = Join-Path $assetFolder 'native-assets.log'
$mode = if ($WithGpu) { '' } else { '--headless' }
$window = if ($WithGpu) { 'Normal' } else { 'Hidden' }
$arguments = "$mode --path `"$app`" --log-file `"$log`" --script res://tests/object_preview.gd -- `"$map`" `"$Game`" `"$assetFolder`""
$proc = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle $window -PassThru
if (-not $proc.WaitForExit(45000)) { $proc.Kill(); throw 'Asset preview timed out.' }
Get-Content -LiteralPath $log -TotalCount 48
if ($proc.ExitCode -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SHADER ERROR|^SCRIPT ERROR|^ERROR:' -Quiet)) {
    throw "Object and terrain texture preview test failed. See $log"
}
