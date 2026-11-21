[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Dotnet)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/bzn-probe-' + [guid]::NewGuid().ToString('N'))) -Force).FullName
Copy-Item -LiteralPath (Join-Path $repo 'BZNTools/BZNParser') -Destination $work -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BznProbe') -Destination $work -Recurse
& $Dotnet build (Join-Path $work 'BznProbe/Probe.csproj') -c Release -o (Join-Path $work 'out') -v quiet -clp:ErrorsOnly
if ($LASTEXITCODE) { throw 'BZNTools build failed.' }
Push-Location (Join-Path $work 'out')
try {
    $measure = [Diagnostics.Stopwatch]::StartNew()
    & $Dotnet ./Probe.dll (Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn') (Join-Path $repo 'map_references/blank_map1/duel_map_27_autosave_01.bzn')
    if ($LASTEXITCODE) { throw 'BZNTools probe failed.' }
    'Wall time ms: {0:N1}; library bytes: {1}' -f $measure.Elapsed.TotalMilliseconds,(Get-Item -LiteralPath ./BZNParser.dll).Length
} finally {
    Pop-Location
}
