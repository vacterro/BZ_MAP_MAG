[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot,
    [string] $WindowsReleaseTemplate,
    [switch] $ToRoot
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
if (-not $WindowsReleaseTemplate) {
    $candidate = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $WindowsReleaseTemplate = $candidate
    } else {
        throw 'Pass -WindowsReleaseTemplate with the Godot windows_release_x86_64.exe template.'
    }
}
$stage = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/desktop-' + [guid]::NewGuid().ToString('N'))) -Force).FullName
$pack = Join-Path $stage 'BZ_MAP_MAG.pck'
$log = Join-Path $stage 'export.log'
$command = "--headless --path `"$app`" --log-file `"$log`" --export-pack `"Windows Desktop`" `"$pack`""
$process = Start-Process -FilePath $Godot -ArgumentList $command -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pack -PathType Leaf)) {
    throw "Godot could not export the pack. See $log"
}
if ($ToRoot) {
    try {
        Copy-Item -LiteralPath $pack -Destination (Join-Path $repo 'BZ_MAP_MAG.pck') -Force
        Copy-Item -LiteralPath $WindowsReleaseTemplate -Destination (Join-Path $repo 'BZ_MAP_MAG.exe') -Force
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-Item -LiteralPath (Join-Path $repo 'BZ_MAP_MAG.exe'), (Join-Path $repo 'BZ_MAP_MAG.pck') | Select-Object Name,Length
    $repo
    return
}
$target = $stage
Copy-Item -LiteralPath $WindowsReleaseTemplate -Destination (Join-Path $target 'BZ_MAP_MAG.exe')
$tools = (New-Item -ItemType Directory -Path (Join-Path $target 'tools')).FullName
foreach ($name in 'Start-Playtest.ps1','Playtest-Assets.ps1','Run-Ownership.ps1','Find-Bzcc.ps1','New-FlatTerrainSnapshot.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $tools
}
$meshPreview = Join-Path $repo 'build/object-preview/mesh-preview.exe'
if (Test-Path -LiteralPath $meshPreview -PathType Leaf) {
    Copy-Item -LiteralPath $meshPreview -Destination $tools
}
Get-ChildItem -LiteralPath $target -File | Select-Object Name,Length
$target
