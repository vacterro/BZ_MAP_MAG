[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Game,
    [Parameter(Mandatory)] [string] $Mission,
    [string] $VrvSource,
    [string] $AssetProfile,
    [string] $ResultFile,
    [string] $PreparedRun,
    [switch] $WaitForGame,
    [switch] $KeepBznLayout,
    [switch] $StartInEditor,
    [switch] $WithoutMissionScript,
    [switch] $ValidateOnly
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Playtest-Assets.ps1')
$preparedRuntime = $null
$junctions = [System.Collections.Generic.List[string]]::new()

function Clear-PreparedRuntime {
    if (-not $preparedRuntime) { return }
    $gameFolder = Get-Item -LiteralPath $preparedRuntime -Force -ErrorAction SilentlyContinue
    if (-not $gameFolder -or $gameFolder.FullName -ne (Join-Path $run 'game') -or
        ($gameFolder.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
    foreach ($path in $junctions) {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        if ($item -and $item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            [IO.Directory]::Delete($item.FullName, $false)
        }
    }
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($gameFolder.FullName)
    while ($pending.Count) {
        foreach ($entry in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
        }
    }
    Remove-Item -LiteralPath $gameFolder.FullName -Recurse -Force
}

trap {
    if ($ResultFile) {
        @{ error = $_.Exception.Message } | ConvertTo-Json -Compress | Set-Content -LiteralPath $ResultFile -Encoding UTF8
    }
    if (-not $gameProcess -or $gameProcess.HasExited) { Clear-PreparedRuntime }
    throw $_
}
$Game = (Resolve-Path -LiteralPath $Game).Path
$Mission = (Resolve-Path -LiteralPath $Mission).Path
$exe = Join-Path $Game 'battlezone2.exe'
if ((Get-Item -LiteralPath $exe).VersionInfo.FileVersion -ne '2.0.185') {
    throw 'This launcher is verified only for the 2.0.185 executable.'
}
if ((Split-Path -Leaf $Mission) -notmatch '^[A-Za-z0-9_][A-Za-z0-9_. -]*\.bzn$') {
    throw 'Unsupported mission filename.'
}
$missionName = Split-Path -Leaf $Mission
$stem = [IO.Path]::GetFileNameWithoutExtension($missionName)
$sourceFolder = Split-Path -Parent $Mission
if ($PreparedRun -and -not $ValidateOnly) {
    $run = (Resolve-Path -LiteralPath $PreparedRun).Path
    $session = Split-Path -Leaf $run
    $clone = Join-Path $run 'game'
    $pack = Join-Path $clone 'snapshot'
    if ($session -notmatch '^BZMAG-[a-f0-9]{32}$' -or $sourceFolder -ne $pack -or -not $WaitForGame) {
        throw 'Invalid prepared Playtest session.'
    }
    foreach ($directory in $run,$clone,$pack) {
        if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Prepared Playtest paths must be private local directories.'
        }
    }
    if (@(Get-ChildItem -LiteralPath $clone -Force).Count -ne 1) { throw 'Prepared Playtest session is already in use.' }
    $preparedRuntime = $clone
}
foreach ($extension in 'ter','trn','inf') {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceFolder "$stem.$extension") -PathType Leaf)) {
        throw "Map snapshot is missing .$extension"
    }
}

# --- Layout stage: classify the BZN before anything else is copied or launched ---
# This mirrors the capability registry in app/formats/bzn_layouts.gd. Direct-native:
# 1192. Conversion sources: 1196 through the VRV bzn_compat adapter. Every other
# version is refused instead of launched unverified, and there is no bypass switch.
$versionLine = Get-Content -LiteralPath $Mission -TotalCount 2 -Encoding ASCII | Select-Object -Last 1
if ($versionLine -notmatch '^[0-9]+$') {
    throw "The BZN header does not name a numeric save version (found '$versionLine')."
}
$bznVersion = [int]$versionLine
$launchRoute = 'refuse'
if ($bznVersion -eq 1192) {
    $launchRoute = 'native'
} elseif ($bznVersion -eq 1196) {
    $launchRoute = 'convert'
}
if ($launchRoute -eq 'refuse') {
    throw "BZN version $bznVersion has no verified 2.0.185 launch route. This launcher runs the native 1192 layout and the adapter-converted 1196 layout; every other version is refused instead of launched unverified."
}
if ($launchRoute -eq 'convert' -and -not $VrvSource) {
    throw 'This 1196 map needs the verified VRV conversion adapter before 2.0.185 can load it. Pass -VrvSource pointing at the VRV checkout with tools/bzn_compat.py. Launching it unconverted fails with SAVEGAME CORRUPT.'
}
if ($launchRoute -eq 'convert' -and $KeepBznLayout) {
    throw '-KeepBznLayout requires a confirmed native 2.0.185 layout (version 1192). This map is version 1196 and needs the verified conversion.'
}

$assetPlan = Get-PlaytestAssetPlan $Game $Mission $AssetProfile $VrvSource ([bool]$WithoutMissionScript)
if ($ValidateOnly) {
    [pscustomobject]@{ LaunchRoute = $launchRoute; BznVersion = $bznVersion; KeepRequested = [bool]$KeepBznLayout; VrvConverterRequired = ($launchRoute -eq 'convert') } | Format-List
    $assetPlan
    return
}
if (Get-Process battlezone2 -ErrorAction SilentlyContinue) { throw 'Close your current Battlezone session before Playtest.' }
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Start Steam before launching this installation.' }

if (-not $PreparedRun) {
    $repo = Split-Path -Parent $PSScriptRoot
    $session = 'BZMAG-' + [guid]::NewGuid().ToString('N')
    $run = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/' + $session)) -Force).FullName
    $clone = (New-Item -ItemType Directory -Path (Join-Path $run 'game')).FullName
    $pack = (New-Item -ItemType Directory -Path (Join-Path $clone 'snapshot')).FullName
    Get-ChildItem -LiteralPath $sourceFolder -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $pack
    }
}
foreach ($extension in 'bzn','ter','trn','inf') {
    if (-not (Test-Path -LiteralPath (Join-Path $pack "$stem.$extension") -PathType Leaf)) {
        throw "Map snapshot is missing .$extension"
    }
}

# --- Conversion stage: materialize the verified 185 layout in the staged snapshot copy ---
$bznCopy = Join-Path $pack $missionName
if ($launchRoute -eq 'convert') {
    $converter = Join-Path (Resolve-Path -LiteralPath $VrvSource).Path 'tools/bzn_compat.py'
    if (-not (Test-Path -LiteralPath $converter -PathType Leaf)) {
        throw "The VRV layout converter is missing at $converter."
    }
    $probe = & python $converter inspect $bznCopy
    if ($LASTEXITCODE) { throw 'VRV could not identify this BZN layout.' }
    $layout = $probe | ConvertFrom-Json
    if ($layout.schema -ne '185') {
        $conversion = Join-Path $run 'migration'
        & python $converter convert $bznCopy --to 185 --output-dir $conversion
        if ($LASTEXITCODE) { throw 'BZN layout review or conversion failed.' }
        Copy-Item -LiteralPath (Join-Path $conversion $missionName) -Destination $bznCopy -Force
        $verify = & python $converter inspect $bznCopy
        if ($LASTEXITCODE) { throw 'The converted BZN could not be re-inspected.' }
        $verified = $verify | ConvertFrom-Json
        if ($verified.schema -ne '185') {
            throw 'The conversion did not produce the verified 185 schema; the original BZN stays untouched.'
        }
    }
}

$extensions = @('.exe','.dll','.cfg','.ini','.fnt','.pak')
Get-ChildItem -LiteralPath $Game -File | Where-Object { $_.Extension -in $extensions } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $clone
}
foreach ($name in 'bz2r_res','bz2r_loc','Missions') {
    $resource = Join-Path $Game $name
    if (-not (Test-Path -LiteralPath $resource -PathType Container)) { throw "Game is missing $name" }
    $link = Join-Path $clone $name
    if ($name -eq 'Missions' -and $assetPlan.MissionDll -and (Split-Path -Parent $assetPlan.MissionDll) -ne $resource) {
        $null = [IO.Directory]::CreateDirectory($link)
        foreach ($native in [IO.Directory]::EnumerateFiles($resource)) {
            Copy-Item -LiteralPath $native -Destination $link
        }
        Copy-Item -LiteralPath $assetPlan.MissionDll -Destination $link -Force
        continue
    }
    New-Item -ItemType Junction -Path $link -Target $resource | Out-Null
    $junctions.Add($link)
}
$assetLines = ''
if ($assetPlan.LuaScript -and -not (Test-Path -LiteralPath (Join-Path $pack (Split-Path -Leaf $assetPlan.LuaScript)))) {
    Copy-Item -LiteralPath $assetPlan.LuaScript -Destination $pack
}
$folders = @($assetPlan.LinkedFolders) + @($assetPlan.VrvFolders)
if ($folders.Count) {
    $localDeps = [IO.Directory]::CreateDirectory((Join-Path $clone 'linkedassets')).FullName
    for ($index = 0; $index -lt $folders.Count; $index++) {
        $folder = $folders[$index]
        $rootPrefix = $folder.TrimEnd('\') + '\'
        if (($run.TrimEnd('\') + '\').StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Asset folder contains the prepared Playtest session: $folder"
        }
        $name = "assets-$index"
        $link = Join-Path $localDeps $name
        New-Item -ItemType Junction -Path $link -Target $folder | Out-Null
        $junctions.Add($link)
        $assetLines += '        AddDirRecurse("@rootdir\linkedassets\' + $name + '");' + [Environment]::NewLine
    }
}
Set-Content -LiteralPath (Join-Path $clone 'steam_appid.txt') -Value '624970' -Encoding ASCII
@"
ConfigureFileSystem()
{
    AppendToMyDocs("$session");
    ConfigureStream("base")
    {
        AddDirRecurse("@rootdir\snapshot");
$assetLines
        AddDirRecurse("@rootdir\bz2r_res");
        AddLangDir("@rootdir\bz2r_loc");
        AddDir("@rootdir\bz2r_loc");
    }
    SetActiveStream("base");
    SetPilotsDirectory("@mydocsdir\pilots");
    SetSavesDirectory("@mydocsdir\saved");
    SetEditorDirectory("@mydocsdir\EditorSaves");
}
"@ | Set-Content -LiteralPath (Join-Path $clone 'bzmag.cfg') -Encoding ASCII
if ($StartInEditor) { $mode = '/startedit' } else { $mode = '' }
$scriptMode = if ($WithoutMissionScript) { '/noscript' } else { '' }
$arguments = "/win /nointro /binarymesh 0 /config bzmag.cfg /logconsole $mode $scriptMode `"$missionName`""
$profile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "My Games/Battlezone Combat Commander/$session"
$gameProcess = Start-Process -FilePath (Join-Path $clone 'battlezone2.exe') -WorkingDirectory $clone -ArgumentList $arguments -WindowStyle Normal -PassThru
$result = [pscustomobject]@{ ProcessId = $gameProcess.Id; Run = $run; Profile = $profile; CommandLine = $arguments; AssetPlan = $assetPlan }
if ($ResultFile) {
    $result | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $ResultFile -Encoding UTF8
}
$result
if ($WaitForGame) {
    $gameProcess.WaitForExit()
    $exitCode = $gameProcess.ExitCode
    Clear-PreparedRuntime
    if ($ResultFile) {
        $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode
        $result | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $ResultFile -Encoding UTF8
    }
}
