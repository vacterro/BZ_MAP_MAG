[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot,
    [Parameter(Mandatory)] [string] $WindowsReleaseTemplate
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$target = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/desktop-' + [guid]::NewGuid().ToString('N'))) -Force).FullName
$pack = Join-Path $target 'BZ_MAP_MAG.pck'
$log = Join-Path $target 'export.log'
$command = "--headless --path `"$app`" --log-file `"$log`" --export-pack `"Windows Desktop`" `"$pack`""
$process = Start-Process -FilePath $Godot -ArgumentList $command -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pack -PathType Leaf)) {
    throw "Godot could not export the pack. See $log"
}
Copy-Item -LiteralPath $WindowsReleaseTemplate -Destination (Join-Path $target 'BZ_MAP_MAG.exe')
$tools = (New-Item -ItemType Directory -Path (Join-Path $target 'tools')).FullName
foreach ($name in 'Start-Playtest.ps1','Playtest-Assets.ps1','Find-Bzcc.ps1','New-FlatTerrainSnapshot.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $tools
}
$meshPreview = Join-Path $repo 'build/object-preview/mesh-preview.exe'
if (Test-Path -LiteralPath $meshPreview -PathType Leaf) {
    Copy-Item -LiteralPath $meshPreview -Destination $tools
}
Get-ChildItem -LiteralPath $target -File | Select-Object Name,Length
$target
