[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $VrvSource,
    [string] $Compiler = 'g++'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$shared = Join-Path (Resolve-Path -LiteralPath $VrvSource).Path 'src/shared'
if (-not (Test-Path -LiteralPath (Join-Path $shared 'MeshIcon.h') -PathType Leaf)) { throw 'The VRV checkout lacks the baked mesh reader.' }
$build = (New-Item -ItemType Directory -Path (Join-Path $repo 'build/object-preview') -Force).FullName
$result = Join-Path $build 'mesh-preview.exe'
& $Compiler -std=c++17 -O2 -municode -static -I $shared (Join-Path $PSScriptRoot 'mesh_preview.cpp') -o $result
if ($LASTEXITCODE) { throw 'Could not compile the local mesh preview adapter.' }
$result
