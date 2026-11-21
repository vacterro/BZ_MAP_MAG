[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Parser,
    [Parameter(Mandatory)] [string] $Source,
    [Parameter(Mandatory)] [string] $Export,
    [Parameter(Mandatory)] [int] $Index
)

$ErrorActionPreference = 'Stop'
$parserPath = (Resolve-Path -LiteralPath $Parser).Path
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$exportPath = (Resolve-Path -LiteralPath $Export).Path
Add-Type -Path $parserPath

function Read-BznPlacement([string] $Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $reader = [BZNParser.Tokenizer.BZNStreamReader]::new($stream, $Path)
        $hints = [BZNParser.Battlezone.BattlezoneBZNHints]::BuildHintsBZ2()
        $map = [BZNParser.Battlezone.BZNFileBattlezone]::new($reader, $hints)
        foreach ($item in $map.Entities) {
            $t = $item.transform
            [pscustomobject]@{
                Odf = $item.PrjID.Value
                Id = $item.seqNo
                Team = $item.team
                Label = $item.label.Value
                Basis = @($t.RightX, $t.RightY, $t.RightZ, $t.RightW, $t.UpX, $t.UpY, $t.UpZ, $t.UpW, $t.FrontX, $t.FrontY, $t.FrontZ, $t.FrontW, $t.PositW)
                Origin = @($t.PositX, $t.PositY, $t.PositZ)
            }
        }
    } finally {
        $stream.Dispose()
    }
}

Push-Location (Split-Path -Parent $parserPath)
try {
    $before = @(Read-BznPlacement $sourcePath)
    $after = @(Read-BznPlacement $exportPath)
} finally {
    Pop-Location
}
if ($before.Count -ne $after.Count -or $Index -lt 0 -or $Index -ge $before.Count) {
    throw 'Unexpected native entity count or index.'
}
foreach ($i in 0..($before.Count - 1)) {
    $original = $before[$i]
    $edited = $after[$i]
    if ($original.Odf -cne $edited.Odf -or $original.Id -ne $edited.Id -or $original.Team -ne $edited.Team -or
        $original.Label -cne $edited.Label -or ($original.Basis -join ',') -ne ($edited.Basis -join ',')) {
        throw "Entity $i metadata or orientation changed."
    }
    $moved = ($original.Origin -join ',') -ne ($edited.Origin -join ',')
    if ($moved -ne ($i -eq $Index)) { throw "Unexpected translation result for entity $i." }
}
$selected = $after[$Index]
[pscustomobject]@{ Entities = $after.Count; Index = $Index; Odf = $selected.Odf; Before = $before[$Index].Origin; After = $selected.Origin }
