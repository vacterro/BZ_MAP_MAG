[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Mission,
    [Parameter(Mandatory)] [string] $VrvTemplate,
    [string] $Destination
)

$ErrorActionPreference = 'Stop'

function Get-SourceDigest([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        [Convert]::ToBase64String($sha.ComputeHash($stream))
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

$source = Get-Item -LiteralPath $Mission
if ($source.Extension -ne '.bzn') { throw 'Select a BZN file.' }
$stem = $source.BaseName
$members = @(Get-ChildItem -LiteralPath $source.DirectoryName -File | Where-Object { $_.BaseName -eq $stem })
foreach ($extension in '.trn','.inf') {
    if ($extension -notin $members.Extension) { throw "Missing $extension companion." }
}
if ('.ter' -in $members.Extension) { throw 'The source already has a TER.' }
$sourceHashes = @{}
foreach ($file in $members) { $sourceHashes[$file.Name] = Get-SourceDigest $file.FullName }
$trn = Get-Content -LiteralPath (Join-Path $source.DirectoryName "$stem.trn") -Raw
$sizeSection = [regex]::Match($trn, '(?im)^\s*\[size\]\s*$(?<body>[^\[]+)')
$fields = @{}
foreach ($match in [regex]::Matches($sizeSection.Groups['body'].Value, '(?im)^\s*(minx|minz|width|depth|height)\s*=\s*(-?\d+(?:\.\d+)?)\s*(?://[^\r\n]*)?$')) {
    $fields[$match.Groups[1].Value] = [double]::Parse($match.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
}
if ($fields.Count -ne 5) { throw 'Expected explicit TRN size, origin and flat height.' }

$template = Get-Item -LiteralPath $VrvTemplate
if ($template.PSIsContainer -or $template.Length -gt (16 + 4194304 / 16)) {
    throw 'The template exceeds the supported terrain size.'
}
$terrain = [IO.File]::ReadAllBytes($template.FullName)
if ($terrain.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($terrain,0,4) -ne 'TERR' -or [BitConverter]::ToUInt32($terrain,4) -ne 5) {
    throw 'Expected a VRV v5 TER template.'
}
$minX = [BitConverter]::ToInt16($terrain,8)
$minZ = [BitConverter]::ToInt16($terrain,10)
$width = [BitConverter]::ToInt16($terrain,12) - $minX
$depth = [BitConverter]::ToInt16($terrain,14) - $minZ
if ($width -le 0 -or $depth -le 0 -or $width % 16 -or $depth % 16 -or ($width * $depth) -gt 4194304 -or $terrain.Length -ne 16 + ($width / 16) * ($depth / 16) * 16) {
    throw 'Flat template dimensions disagree with the file length.'
}
$height = [BitConverter]::ToSingle($terrain,17)
$heightDifference = [Math]::Abs($height - $fields.height)
if ($terrain[16] -ne 0 -or [single]::IsNaN($height) -or [single]::IsInfinity($height) -or 2 * $minX -ne $fields.minx -or 2 * $minZ -ne $fields.minz -or 2 * $width -ne $fields.width -or 2 * $depth -ne $fields.depth -or $heightDifference -gt 0.0001) {
    throw 'Template origin, dimensions and flat height must match the source TRN.'
}
$first = [BitConverter]::ToString($terrain,16,16)
for ($offset = 32; $offset -lt $terrain.Length; $offset += 16) {
    if ([BitConverter]::ToString($terrain,$offset,16) -ne $first) { throw 'The terrain template is not uniform.' }
}
if (-not $Destination) {
    $repo = Split-Path -Parent $PSScriptRoot
    $build = [IO.Directory]::CreateDirectory((Join-Path $repo 'build'))
    $Destination = Join-Path $build.FullName ('flat-' + [guid]::NewGuid().ToString('N'))
}
$Destination = [IO.Path]::GetFullPath($Destination)
$parent = Split-Path -Parent $Destination
if (-not [IO.Directory]::Exists($parent) -or (Test-Path -LiteralPath $Destination)) {
    throw 'Choose a new map folder in an existing destination directory.'
}
$stage = Join-Path $parent ('.bzmag-flat-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($stage)
try {
    foreach ($file in $members) {
        $expected = $sourceHashes[$file.Name]
        $copied = Join-Path $stage $file.Name
        Copy-Item -LiteralPath $file.FullName -Destination $copied
        if ((Get-SourceDigest $copied) -cne $expected -or (Get-SourceDigest $file.FullName) -cne $expected) {
            throw "Source changed while copying $($file.Name)."
        }
    }
    [IO.File]::WriteAllBytes((Join-Path $stage "$stem.ter"), $terrain)
    [IO.Directory]::Move($stage, $Destination)
} finally {
    if ([IO.Directory]::Exists($stage)) {
        foreach ($file in [IO.Directory]::EnumerateFiles($stage)) { Remove-Item -LiteralPath $file -Force }
        [IO.Directory]::Delete($stage)
    }
}
Join-Path $Destination $source.Name
