[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Game,
    [Parameter(Mandatory)] [string] $Mission,
    [string] $Godot,
    [string] $VrvSource,
    [string] $Converter,
    [string] $ModProfile,
    [string] $MissionProfile,
    [string[]] $AssetRoots = @(),
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
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')
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

function Get-ValidatedPackage([string] $MissionPath) {
    $root = Split-Path -Parent $PSScriptRoot
    $app = Join-Path $root 'app'
    $validator = $Godot
    $project = ''
    if (Test-Path -LiteralPath (Join-Path $app 'project.godot') -PathType Leaf) {
        if (-not $validator) {
            $rootExe = Join-Path $root 'BZ_MAP_MAG.exe'
            if ((Test-Path -LiteralPath $rootExe -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $root 'BZ_MAP_MAG.pck') -PathType Leaf)) {
                $validator = $rootExe
            } else {
                $validator = (Get-Command godot.exe -ErrorAction SilentlyContinue).Source
            }
        }
        if (-not $validator) { throw 'Pass -Godot with the Godot executable used by this checkout.' }
        if ((Split-Path -Leaf $validator) -ine 'BZ_MAP_MAG.exe') {
            $project = "--path `"$app`""
        } else {
            $valDir = Split-Path -Parent (Resolve-Path -LiteralPath $validator).Path
            $pckFile = Join-Path $valDir 'BZ_MAP_MAG.pck'
            $manifestFile = Join-Path $valDir 'BZ_MAP_MAG.manifest.json'
            if (-not (Test-Path -LiteralPath $pckFile -PathType Leaf) -or -not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
                throw 'Stale or unverified packaged validator: BZ_MAP_MAG.manifest.json is missing. Rebuild with tools/Build-Desktop.ps1 -ToRoot or pass -Godot.'
            }
            $manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $liveDigest = Get-BzmagAppSourceDigest $app
            $livePckHash = (Get-FileHash -LiteralPath $pckFile -Algorithm SHA256).Hash.ToLowerInvariant()
            $liveExeHash = (Get-FileHash -LiteralPath $validator -Algorithm SHA256).Hash.ToLowerInvariant()
            $exeMismatch = ($manifest.PSObject.Properties.Name -contains 'exeSha256') -and $manifest.exeSha256 -and ($manifest.exeSha256 -ne $liveExeHash)
            if ($manifest.sourceDigest -ne $liveDigest -or $manifest.pckSha256 -ne $livePckHash -or $exeMismatch) {
                throw 'Stale or unverified packaged validator: BZ_MAP_MAG.pck or BZ_MAP_MAG.exe does not match live app/ sources. Rebuild with tools/Build-Desktop.ps1 -ToRoot or pass -Godot.'
            }
        }
    } elseif (-not $validator) {
        $validator = Join-Path $root 'BZ_MAP_MAG.exe'
    }
    $validator = (Resolve-Path -LiteralPath $validator).Path
    $response = [IO.Path]::GetTempFileName()
    $log = "$response.log"
    try {
        $argsLine = "--headless $project --log-file `"$log`" -- --validate-playtest `"$MissionPath`" `"$response`""
        $process = Start-Process -FilePath $validator -ArgumentList $argsLine -WorkingDirectory $root -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Playtest package validation timed out.'
        }
        if ($process.ExitCode -ne 0 -or (Get-Item -LiteralPath $response).Length -eq 0) {
            $detail = if (Test-Path -LiteralPath $log) { (Get-Content -LiteralPath $log -Tail 6) -join ' ' }
            throw "Playtest package validator failed. $detail"
        }
        return Get-Content -LiteralPath $response -Raw -Encoding UTF8 | ConvertFrom-Json
    } finally {
        Remove-Item -LiteralPath $response,$log -Force -ErrorAction SilentlyContinue
    }
}

trap {
    $failure = $_
    if ($ResultFile) {
        try { Write-BzmagJsonFile $ResultFile @{ error = $failure.Exception.Message } }
        catch { Write-Warning "Could not write Playtest failure status. $($_.Exception.Message)" }
    }
    if (-not $gameProcess -or $gameProcess.HasExited) { Clear-PreparedRuntime }
    throw $failure
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
$package = Get-ValidatedPackage $Mission
if ($package.error) { throw $package.error }
$launchRoute = $package.route
$bznVersion = $package.version
if ($launchRoute -notin 'native','convert' -or -not $package.files) { throw 'Invalid Playtest validation result.' }
if ($launchRoute -eq 'convert' -and $KeepBznLayout) {
    throw '-KeepBznLayout requires a confirmed native 2.0.185 layout (version 1192). This map is version 1196 and needs the verified conversion.'
}
if ($launchRoute -eq 'convert') {
    $converterArg = if ($Converter) { $Converter } else { $VrvSource }
    if (-not $converterArg) {
        throw 'This 1196 map needs the verified VRV conversion adapter. Pass -Converter (or legacy -VrvSource) pointing at the converter checkout with tools/bzn_compat.py.'
    }
    $resolvedConv = (Resolve-Path -LiteralPath $converterArg).Path
    $converter = if ((Test-Path -LiteralPath $resolvedConv -PathType Leaf) -and $resolvedConv.EndsWith('.py', [StringComparison]::OrdinalIgnoreCase)) {
        $resolvedConv
    } else {
        Join-Path $resolvedConv 'tools/bzn_compat.py'
    }
    if (-not (Test-Path -LiteralPath $converter -PathType Leaf)) {
        throw "The VRV layout converter is missing at $converter."
    }
    $probe = & python $converter inspect $Mission
    if ($LASTEXITCODE) { throw 'VRV could not identify this BZN layout.' }
    $layout = $probe | ConvertFrom-Json
}

$odfs = if ($package.PSObject.Properties.Name -contains 'odfs') { @($package.odfs) } else { @() }
$assetPlan = Get-PlaytestAssetPlan $Game $Mission $AssetProfile $VrvSource ([bool]$WithoutMissionScript) $AssetRoots $odfs '' $ModProfile $Converter
if ($ValidateOnly) {
    return $assetPlan | Add-Member -PassThru -NotePropertyMembers @{
        LaunchRoute = $launchRoute
        BznVersion = $bznVersion
        MissionProfile = $MissionProfile
        KeepRequested = [bool]$KeepBznLayout
        VrvConverterRequired = ($launchRoute -eq 'convert')
    }
}
if (Get-Process battlezone2 -ErrorAction SilentlyContinue) { throw 'Close your current Battlezone session before Playtest.' }
if (-not (Get-Process steam -ErrorAction SilentlyContinue)) { throw 'Start Steam before launching this installation.' }

if (-not $PreparedRun) {
    $repo = Split-Path -Parent $PSScriptRoot
    $session = 'BZMAG-' + [guid]::NewGuid().ToString('N')
    $run = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/' + $session)) -Force).FullName
    $clone = (New-Item -ItemType Directory -Path (Join-Path $run 'game')).FullName
    $preparedRuntime = $clone
    $pack = (New-Item -ItemType Directory -Path (Join-Path $clone 'snapshot')).FullName
    Get-ChildItem -LiteralPath $sourceFolder -File | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $pack
    }
}
foreach ($file in $package.files.PSObject.Properties) {
    $staged = Join-Path $pack $file.Name
    if (-not (Test-Path -LiteralPath $staged -PathType Leaf) -or
        (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash -ne $file.Value) {
        throw "Map snapshot changed after validation: $($file.Name)"
    }
}

# --- Conversion stage: materialize the verified 185 layout in the staged snapshot copy ---
$bznCopy = Join-Path $pack $missionName
if ($launchRoute -eq 'convert') {
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
$folders = @($assetPlan.AssetRoots)
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
try {
    $null = New-BzmagRunRecord (Split-Path -Parent $PSScriptRoot) $run $gameProcess
} catch {
    Write-Warning "Could not record Playtest process ownership for $session. $($_.Exception.Message)"
}
$result = [pscustomobject]@{ ProcessId = $gameProcess.Id; Run = $run; Profile = $profile; CommandLine = $arguments; AssetPlan = $assetPlan }
if ($ResultFile) {
    Write-BzmagJsonFile $ResultFile $result
}
$result
if ($WaitForGame) {
    $gameProcess.WaitForExit()
    $exitCode = $gameProcess.ExitCode
    Clear-PreparedRuntime
    if ($ResultFile) {
        $result | Add-Member -NotePropertyName ExitCode -NotePropertyValue $exitCode
        Write-BzmagJsonFile $ResultFile $result
    }
}
