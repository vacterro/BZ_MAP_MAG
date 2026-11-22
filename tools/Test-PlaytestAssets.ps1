[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Game,
    [Parameter(Mandatory)] [string] $Godot,
    [Parameter(Mandatory)] [string] $VrvSource
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $PSScriptRoot 'Start-Playtest.ps1'
$common = @{ Game = $Game; Godot = $Godot; VrvSource = $VrvSource }
$source = Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'
$stock = & $launcher @common -Mission $source -ValidateOnly
if ($stock.ScriptCheck -ne 'resolved' -or (Split-Path -Leaf $stock.MissionDll) -ne 'strategy02.dll') {
    throw 'The stock mission DLL did not resolve.'
}
$parent = [IO.Directory]::CreateDirectory((Join-Path $repo 'build')).FullName
$root = [IO.Directory]::CreateDirectory((Join-Path $parent ('asset-test-' + [guid]::NewGuid().ToString('N')))).FullName
$map = [IO.Directory]::CreateDirectory((Join-Path $root 'map')).FullName
foreach ($item in Get-ChildItem -LiteralPath (Split-Path -Parent $source) -File) { Copy-Item -LiteralPath $item.FullName -Destination $map }
$mission = Join-Path $map 'braveliltoaster.bzn'
$assetRoot = [IO.Directory]::CreateDirectory((Join-Path $root 'linked assets')).FullName
$profile = Join-Path $root 'brave.json'
[IO.File]::WriteAllText($profile, '{"folders":["linked assets"]}')
$encoding = [Text.Encoding]::GetEncoding(28591)
$original = $encoding.GetString([IO.File]::ReadAllBytes($source))

function Expect-Refusal([string] $Text, [scriptblock] $Action) {
    try {
        $null = & $Action
    } catch {
        if ($_.Exception.Message.Contains($Text)) { return }
        throw
    }
    throw "Expected a Playtest refusal containing $Text."
}

$blank = Join-Path $repo 'map_references/blank_map1/duel_map_27_autosave_01.bzn'
$template = Join-Path $VrvSource 'mod/Data/Templates/vrv_new_blank.ter'
$flat = & (Join-Path $PSScriptRoot 'New-FlatTerrainSnapshot.ps1') -Mission $blank -VrvTemplate $template -Destination (Join-Path $root 'native')
$native = & $launcher @common -Mission $flat -ValidateOnly
if ($native.LaunchRoute -ne 'native' -or $stock.LaunchRoute -ne 'convert' -or -not $native.ResolvedOdfs.ContainsKey('ivtank_vsr.odf')) {
    throw 'Verified BZN layouts did not select their expected launch routes or resolve ivtank_vsr.odf.'
}
# Converter vs asset root separation: 1192 native resolves VSR ODFs via -AssetRoots without needing -VrvSource,
# and refuses cleanly before launch when neither VSR nor -AssetRoots provides ivtank_vsr.odf.
$vsrDeps = Join-Path $Game 'VRV/deps/3532748119'
if (Test-Path -LiteralPath $vsrDeps -PathType Container) {
    Expect-Refusal 'Missing object ODF dependencies: ivtank_vsr.odf' { & $launcher -Game $Game -Godot $Godot -Mission $flat -ValidateOnly }
    $separated = & $launcher -Game $Game -Godot $Godot -AssetRoots @($native.VrvFolders) -Mission $flat -ValidateOnly
    if ($separated.LaunchRoute -ne 'native' -or $separated.ConverterRoot -ne '' -or -not $separated.ResolvedOdfs.ContainsKey('ivtank_vsr.odf')) {
        throw '1192 native launch failed to resolve ODFs through explicit -AssetRoots without -VrvSource.'
    }
    # Semicolon-delimited -AssetRoots across PowerShell -File process boundary (editor.gd OS.create_process contract, T-17).
    $multiJoined = (@($assetRoot) + @($native.VrvFolders)) -join ';'
    $cliOut = & powershell.exe -NoProfile -NonInteractive -File $launcher -Game $Game -Godot $Godot -AssetRoots $multiJoined -Mission $flat -ValidateOnly 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("powershell.exe -File failed to parse semicolon-delimited -AssetRoots: " + ($cliOut | Out-String))
    }
    # Strict Stock isolation: -ModProfile 'stock' must NEVER mount VRV/VSR assets even if -Converter or -VrvSource is provided.
    Expect-Refusal 'Missing object ODF dependencies: ivtank_vsr.odf' {
        & $launcher -Game $Game -Godot $Godot -ModProfile 'stock' -Converter $VrvSource -VrvSource $VrvSource -Mission $flat -ValidateOnly
    }
    # Separate -ModProfile 'vsr' resolves VSR ODFs via Workshop 1325933293 without requiring -VrvSource.
    $vsrWs = [IO.Path]::GetFullPath((Join-Path $Game '../../workshop/content/624970/1325933293'))
    if (Test-Path -LiteralPath $vsrWs -PathType Container) {
        $vsrPlan = & $launcher -Game $Game -Godot $Godot -ModProfile 'vsr' -Mission $flat -ValidateOnly
        if ($vsrPlan.LaunchRoute -ne 'native' -or $vsrPlan.ConverterRoot -ne '' -or -not $vsrPlan.ResolvedOdfs.ContainsKey('ivtank_vsr.odf')) {
            throw 'ModProfile vsr failed to resolve VSR ODFs independently of -VrvSource.'
        }
    }
}
# Wave 1 & 2: Stock 1192 Playtest independence from stale/absent -VrvSource + unified bzmag.compatibility-result/1 + DLL SHA-256 identity.
$plgr = Join-Path $Game 'maps/Missions/Instant/PLGR/plgr.bzn'
if (Test-Path -LiteralPath $plgr -PathType Leaf) {
    $plgrCopy = [IO.Directory]::CreateDirectory((Join-Path $root 'plgr-stock')).FullName
    foreach ($item in Get-ChildItem -LiteralPath (Split-Path -Parent $plgr) -File) {
        Copy-Item -LiteralPath $item.FullName -Destination $plgrCopy
    }
    if (-not (Test-Path -LiteralPath (Join-Path $plgrCopy 'plgr.inf') -PathType Leaf)) {
        [IO.File]::WriteAllText((Join-Path $plgrCopy 'plgr.inf'), "[DESCRIPTION]`r`nmissionName = `"plgr`"`r`n")
    }
    if (-not (Test-Path -LiteralPath (Join-Path $plgrCopy 'plgr.lua') -PathType Leaf)) {
        [IO.File]::WriteAllText((Join-Path $plgrCopy 'plgr.lua'), "-- Test-only Lua stub; never launched.`r`n")
    }
    $staleStock = & $launcher -Game $Game -Godot $Godot -ModProfile 'stock' -VrvSource 'Z:/nonexistent_stale_vrv_checkout' -Mission (Join-Path $plgrCopy 'plgr.bzn') -ValidateOnly
    if ($staleStock.LaunchRoute -ne 'native' -or $staleStock.ConverterRoot -ne '' -or $staleStock.VrvFolders.Count -ne 0) {
        throw 'Stock 1192 Playtest failed to decouple from stale/invalid -VrvSource.'
    }
    if ($null -eq $staleStock.Compatibility -or $staleStock.Compatibility.schema -ne 'bzmag.compatibility-result/1') {
        throw 'Start-Playtest -ValidateOnly did not emit unified bzmag.compatibility-result/1 contract.'
    }
    if ($null -eq $staleStock.DllIdentity -or $staleStock.DllIdentity.Status -ne 'VERIFIED_EXACT') {
        throw "Stock 1192 LuaMission.dll SHA-256 identity check did not verify as VERIFIED_EXACT (got $($staleStock.DllIdentity.Status))."
    }
    # Wave 1 PS checks: renamed Instant.dll -> Strategy02.dll is DLL_NAME_MISMATCH; mismatched -MissionProfile is MISSION_PROFILE_MISMATCH!
    $psRenamed = Join-Path $root 'ps-renamed-dll'
    $null = [IO.Directory]::CreateDirectory($psRenamed)
    Copy-Item -LiteralPath (Join-Path $Game 'Missions/Instant.dll') -Destination (Join-Path $psRenamed 'Strategy02.dll') -Force
    . (Join-Path $PSScriptRoot 'Playtest-Assets.ps1')
    $renId = Get-DllIdentityInfo (Join-Path $psRenamed 'Strategy02.dll') 'stock' 'Strategy02.dll' 'strategy' 'Strategy02.dll'
    if ($renId.Status -ne 'DLL_NAME_MISMATCH' -or $renId.Verified) {
        throw "Renamed Stock Instant.dll -> Strategy02.dll must be DLL_NAME_MISMATCH, got $($renId.Status)."
    }
    $misId = Get-DllIdentityInfo (Join-Path $Game 'Missions/Instant.dll') 'stock' 'Strategy02.dll' 'strategy' 'Instant.dll'
    if ($misId.Status -ne 'MISSION_PROFILE_MISMATCH' -or $misId.Verified) {
        throw "Actual Instant.dll with Strategy mission profile must be MISSION_PROFILE_MISMATCH, got $($misId.Status)."
    }
    $inhVrv = Get-DllIdentityInfo (Join-Path $Game 'Missions/LuaMission.dll') 'vrv' 'LuaMission.dll' 'lua' 'LuaMission.dll'
    if ($inhVrv.Status -ne 'VERIFIED_EXPLICIT_INHERITANCE' -or -not $inhVrv.Verified) {
        throw "Explicit Stock LuaMission.dll inheritance under VRV must be VERIFIED_EXPLICIT_INHERITANCE, got $($inhVrv.Status)."
    }
    # Start-Playtest -ValidateOnly with mismatched MissionProfile surfaces MISSION_PROFILE_MISMATCH
    $misPlan = & $launcher -Game $Game -Godot $Godot -ModProfile 'stock' -MissionProfile 'strategy' -Mission (Join-Path $plgrCopy 'plgr.bzn') -ValidateOnly
    if ($misPlan.DllIdentity.Status -ne 'MISSION_PROFILE_MISMATCH' -or $misPlan.Compatibility.validationStatus -ne 'MISSION_UNVERIFIED') {
        throw "Start-Playtest -ValidateOnly failed to detect MISSION_PROFILE_MISMATCH for plgr LuaMission.dll under strategy profile."
    }
}
# Cached ODF index reuse + invalidation + same-size loose modification + ambiguity + packed DOCP .pak support.
. (Join-Path $PSScriptRoot 'Playtest-Assets.ps1')
# Wave 2 PS checks: same-size loose ODF edit + timestamp collision invalidates Get-AssetRootStamp, and real smtex.pak zlib read works!
$psStampRoot = [IO.Directory]::CreateDirectory((Join-Path $root 'ps-stamp-inv')).FullName
$psOdf = Join-Path $psStampRoot 'unit_x.odf'
[IO.File]::WriteAllText($psOdf, '[GameObjectClass] AAA')
$fixedTime = [DateTime]::new(2020, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
[IO.File]::SetLastWriteTimeUtc($psOdf, $fixedTime)
$stampA = Get-AssetRootStamp $psStampRoot $true
[IO.File]::WriteAllText($psOdf, '[GameObjectClass] BBB')
[IO.File]::SetLastWriteTimeUtc($psOdf, $fixedTime)
$stampB = Get-AssetRootStamp $psStampRoot $true
if ($stampA -eq $stampB) {
    throw 'Get-AssetRootStamp failed to invalidate on same-size + forced-timestamp-collision ODF edit.'
}
# Content hashing must not stop at 512 tracked files: a same-size rewrite with a
# forced identical timestamp deep in a large root must still invalidate the stamp.
$largeRoot = [IO.Directory]::CreateDirectory((Join-Path $root 'ps-stamp-large')).FullName
for ($i = 0; $i -lt 600; $i++) {
    [IO.File]::WriteAllText((Join-Path $largeRoot ('unit_{0:d4}.odf' -f $i)), '[GameObjectClass] AAA')
}
$largeTarget = Join-Path $largeRoot 'unit_0599.odf'
[IO.File]::SetLastWriteTimeUtc($largeTarget, $fixedTime)
$largeStampA = Get-AssetRootStamp $largeRoot $true
[IO.File]::WriteAllText($largeTarget, '[GameObjectClass] BBB')
[IO.File]::SetLastWriteTimeUtc($largeTarget, $fixedTime)
$largeStampB = Get-AssetRootStamp $largeRoot $true
if ($largeStampA -eq $largeStampB) {
    throw 'Get-AssetRootStamp failed to invalidate on same-size + forced-timestamp-collision ODF edit in a 600-file root.'
}
$smtexPath = Join-Path $Game 'smtex.pak'
if (Test-Path -LiteralPath $smtexPath -PathType Leaf) {
    $pakRead = Read-DocpPakEntry $smtexPath 'bane2.tga' 65536
    if (-not $pakRead.Ok -or $pakRead.Bytes.Length -ne 49196) {
        throw "Read-DocpPakEntry failed to decompress real smtex.pak::bane2.tga (err=$($pakRead.Error))."
    }
}
# A stored DOCP entry can carry a zlib wrapper even when packedSize == unpackedSize.
$wrappedPak = Join-Path $root 'wrapped-stored.pak'
$wrappedPayload = [byte[]]@(
    0x78,0x9C,0x8B,0x76,0x4F,0xCC,0x4D,0xF5,0x4F,0xCA,0x4B,0x4D,0x2E,0x71,0xCE,0x49,
    0x2C,0x2E,0x8E,0xE5,0x02,0x00,0x3F,0x89,0x06,0x8A
)
$wrappedDocp = [IO.MemoryStream]::new()
$wrappedWriter = [IO.BinaryWriter]::new($wrappedDocp)
$wrappedWriter.Write([Text.Encoding]::ASCII.GetBytes('DOCP'))
$wrappedWriter.Write([uint32]2); $wrappedWriter.Write([uint32]0); $wrappedWriter.Write([uint32]0)
$wrappedWriter.Write([uint32]1); $wrappedWriter.Write([uint32]0)
for ($pad = 0; $pad -lt 8; $pad++) { $wrappedWriter.Write([byte]0) }
$wrappedWriter.Write($wrappedPayload)
$wrappedDir = [uint32]$wrappedDocp.Position
$wrappedWriter.BaseStream.Position = 20
$wrappedWriter.Write([uint32]$wrappedDir)
$wrappedWriter.BaseStream.Position = $wrappedDir
$wrappedName = [Text.Encoding]::ASCII.GetBytes('wrapped.odf')
$wrappedWriter.Write([uint32]0); $wrappedWriter.Write([byte]$wrappedName.Length); $wrappedWriter.Write($wrappedName)
$wrappedWriter.Write([uint32]32); $wrappedWriter.Write([uint32]26); $wrappedWriter.Write([uint32]26)
$wrappedWriter.Flush()
[IO.File]::WriteAllBytes($wrappedPak, $wrappedDocp.ToArray())
$wrappedWriter.Dispose(); $wrappedDocp.Dispose()
$wrappedRead = Read-DocpPakEntry $wrappedPak 'wrapped.odf' 65536
if ($wrappedRead.Ok -or $wrappedRead.Status -ne 'ENTRY_CORRUPT') {
    throw "Read-DocpPakEntry reported a zlib-wrapped, size-mismatched stored entry as readable (status=$($wrappedRead.Status))."
}
# Wave 2 & 6: Recursive Workshop dependency graph & real installed custom Workshop mods + DLL SHA-256 mismatch detection.
$wrongDll = Join-Path $root 'Strategy02.dll'
[IO.File]::WriteAllText($wrongDll, 'WRONG_HASH_DLL_BODY')
$wrongIdent = Get-DllIdentityInfo $wrongDll 'stock'
if ($wrongIdent.Status -ne 'HASH_UNVERIFIED') {
    throw "Mutated Strategy02.dll should be HASH_UNVERIFIED, got $($wrongIdent.Status)."
}
$wsRoot = [IO.Path]::GetFullPath((Join-Path $Game '../../workshop/content/624970'))
if (Test-Path -LiteralPath $wsRoot -PathType Container) {
    $vsrGraph = Get-WorkshopDependencyGraph $Game 'vsr'
    if ($vsrGraph.Roots.Count -lt 2) {
        throw 'Real VSR Workshop dependency graph did not resolve child asset dependencies.'
    }
    if (Test-Path -LiteralPath (Join-Path $wsRoot '3820486276') -PathType Container) {
        $vrvGraph = Get-WorkshopDependencyGraph $Game 'vrv'
        if ($vrvGraph.Roots.Count -lt 5) {
            throw 'Real VRV Workshop dependency graph did not resolve declared dependencies.'
        }
    }
    $customChecked = 0
    foreach ($cid in '3493433992','3728347411','2319244444') {
        if (Test-Path -LiteralPath (Join-Path $wsRoot $cid) -PathType Container) {
            $cg = Get-WorkshopDependencyGraph $Game ("custom:ws-$cid")
            if ($cg.Roots.Count -lt 2) {
                throw "Real custom Workshop mod $cid did not traverse transitive asset dependencies."
            }
            $customChecked++
        }
    }
    if ($customChecked -lt 2) {
        throw "Expected at least 2 real installed custom Workshop mods to verify recursive traversal, found $customChecked."
    }
}
$cacheRoot = Join-Path $root 'asset-cache'
$synthRoot = [IO.Directory]::CreateDirectory((Join-Path $root 'synth-assets')).FullName
$subA = [IO.Directory]::CreateDirectory((Join-Path $synthRoot 'subA')).FullName
$subB = [IO.Directory]::CreateDirectory((Join-Path $synthRoot 'subB')).FullName
[IO.File]::WriteAllText((Join-Path $subA 'ivtank_vsr.odf'), '[GameObjectClass]')
$synthMissionDir = [IO.Directory]::CreateDirectory((Join-Path $root 'synth-mission')).FullName
$synthMission = Join-Path $synthMissionDir 'dummy.bzn'
[IO.File]::WriteAllText($synthMission, '')
$firstPlan = Get-PlaytestAssetPlan $Game $synthMission '' '' $true @($synthRoot) @('ivtank_vsr.odf') $cacheRoot
if ($firstPlan.CacheMisses -lt 1 -or -not $firstPlan.ResolvedOdfs.ContainsKey('ivtank_vsr.odf')) {
    throw 'Initial asset index build did not resolve ivtank_vsr.odf.'
}
$secondPlan = Get-PlaytestAssetPlan $Game $synthMission '' '' $true @($synthRoot) @('ivtank_vsr.odf') $cacheRoot
if ($secondPlan.CacheHits -lt 1 -or $secondPlan.CacheMisses -ne 0) {
    throw 'Second asset preflight call did not reuse the cached ODF index.'
}
# Add a duplicate ODF in subB -> directory stamp changes, cache invalidates, ambiguity is reported.
[IO.File]::WriteAllText((Join-Path $subB 'ivtank_vsr.odf'), '[GameObjectClass]')
$ambigPlan = Get-PlaytestAssetPlan $Game $synthMission '' '' $true @($synthRoot) @('ivtank_vsr.odf') $cacheRoot
if ($ambigPlan.CacheMisses -lt 1 -or $ambigPlan.AmbiguousOdfs.Count -ne 1) {
    throw 'Cache invalidation or ambiguous ODF detection failed after adding duplicate ODF.'
}
# Packed DOCP v2 .pak resolution without a loose ODF file on disk.
$pakRoot = [IO.Directory]::CreateDirectory((Join-Path $root 'pak-assets')).FullName
$pakPath = Join-Path $pakRoot 'custom.pak'
$entryName = [Text.Encoding]::ASCII.GetBytes('packed_unit.odf')
$ms = [IO.MemoryStream]::new()
$bw = [IO.BinaryWriter]::new($ms)
$bw.Write([Text.Encoding]::ASCII.GetBytes('DOCP'))
$bw.Write([uint32]2); $bw.Write([uint32]0); $bw.Write([uint32]0)
$bw.Write([uint32]1); $bw.Write([uint32]32); $bw.Write([uint32]0); $bw.Write([uint32]0)
$bw.Write([uint32]1); $bw.Write([byte]$entryName.Length); $bw.Write($entryName)
$bw.Write([uint32]0); $bw.Write([uint32]0); $bw.Write([uint32]0)
$bw.Flush()
[IO.File]::WriteAllBytes($pakPath, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()
$pakPlan = Get-PlaytestAssetPlan $Game $synthMission '' '' $true @($pakRoot) @('packed_unit.odf') $cacheRoot
if ($pakPlan.ResolvedOdfs['packed_unit.odf'] -ne "${pakPath}::packed_unit.odf") {
    throw 'Packed DOCP .pak ODF resource was not resolved without a false refusal.'
}
# Stale-PCK/helper refusal check: when -Godot is omitted or points to BZ_MAP_MAG.exe with a mismatched manifest (source, pck, exe, or helpersDigest), Start-Playtest refuses stale packaged code.
$manifestFile = Join-Path $repo 'BZ_MAP_MAG.manifest.json'
$hadManifest = Test-Path -LiteralPath $manifestFile -PathType Leaf
$savedManifestBytes = if ($hadManifest) { [IO.File]::ReadAllBytes($manifestFile) } else { $null }
if ((Test-Path -LiteralPath (Join-Path $repo 'BZ_MAP_MAG.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $repo 'BZ_MAP_MAG.pck') -PathType Leaf)) {
    try {
        [IO.File]::WriteAllText($manifestFile, '{"schema":"bzmag.build-manifest/3","sourceDigest":"stale000","pckSha256":"stale000","helpersDigest":"stale000"}', [Text.Encoding]::UTF8)
        Expect-Refusal 'Stale or unverified packaged validator' {
            & $launcher -Game $Game -VrvSource $VrvSource -Mission $source -ValidateOnly
        }
        $liveAppDig = Get-BzmagAppSourceDigest (Join-Path $repo 'app')
        $livePckDig = (Get-FileHash -LiteralPath (Join-Path $repo 'BZ_MAP_MAG.pck') -Algorithm SHA256).Hash.ToLowerInvariant()
        $liveExeDig = (Get-FileHash -LiteralPath (Join-Path $repo 'BZ_MAP_MAG.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($manifestFile, "{`"schema`":`"bzmag.build-manifest/3`",`"sourceDigest`":`"$liveAppDig`",`"pckSha256`":`"$livePckDig`",`"exeSha256`":`"$liveExeDig`",`"helpersDigest`":`"tamperedhelperdigest`"}", [Text.Encoding]::UTF8)
        Expect-Refusal 'Stale or unverified packaged validator' {
            & $launcher -Game $Game -VrvSource $VrvSource -Mission $source -ValidateOnly
        }
    } finally {
        if ($hadManifest) {
            [IO.File]::WriteAllBytes($manifestFile, $savedManifestBytes)
        } else {
            Remove-Item -LiteralPath $manifestFile -Force -ErrorAction SilentlyContinue
        }
    }
}

$nativeBytes = [IO.File]::ReadAllBytes($flat)
[IO.File]::WriteAllBytes($flat, [byte[]]($nativeBytes[0..20]))
Expect-Refusal 'BZN header is malformed' { & $launcher @common -Mission $flat -ValidateOnly }
[IO.File]::WriteAllBytes($flat, [byte[]]($nativeBytes[0..127]))
Expect-Refusal 'do not match the verified layout' { & $launcher @common -Mission $flat -ValidateOnly }
[IO.File]::WriteAllBytes($flat, $nativeBytes)
$flatTer = [IO.Path]::ChangeExtension($flat, 'ter')
[IO.File]::WriteAllBytes($flatTer, [byte[]]::new(0))
Expect-Refusal 'TER' { & $launcher @common -Mission $flat -ValidateOnly }
Copy-Item -LiteralPath $template -Destination $flatTer -Force
Expect-Refusal 'needs the verified VRV conversion adapter' { & $launcher -Game $Game -Godot $Godot -Mission $source -ValidateOnly }
Expect-Refusal 'converter is missing' { & $launcher -Game $Game -Godot $Godot -VrvSource $root -Mission $source -ValidateOnly }
Expect-Refusal 'requires a confirmed native' { & $launcher @common -Mission $source -KeepBznLayout -ValidateOnly }

$custom = 'Audit00000.dll'
[IO.File]::WriteAllBytes($mission, $encoding.GetBytes($original.Replace('strategy02.dll', $custom)))
Expect-Refusal "Missing mission DLL $custom" { & $launcher @common -Mission $mission -AssetProfile $profile -ValidateOnly }
Copy-Item -LiteralPath $stock.MissionDll -Destination (Join-Path $assetRoot $custom)
$linked = & $launcher @common -Mission $mission -AssetProfile $profile -ValidateOnly
if ($linked.MissionDll -ne (Join-Path $assetRoot $custom) -or $linked.LinkedFolders[0] -ne $assetRoot) {
    throw 'The relative asset profile did not resolve the custom DLL.'
}

[IO.File]::WriteAllBytes($mission, $encoding.GetBytes($original.Replace('strategy02.dll', 'LuaMission.dll')))
Expect-Refusal 'Missing Lua mission script braveliltoaster.lua' { & $launcher @common -Mission $mission -AssetProfile $profile -ValidateOnly }
$skipped = & $launcher @common -Mission $mission -AssetProfile $profile -WithoutMissionScript -ValidateOnly
if ($skipped.ScriptCheck -ne 'disabled' -or $skipped.LuaScript) { throw 'Explicit no-script mode checked a Lua dependency.' }
[IO.File]::WriteAllText((Join-Path $assetRoot 'braveliltoaster.lua'), '-- Test-only Lua resource; this test never launches the game.')
$lua = & $launcher @common -Mission $mission -AssetProfile $profile -ValidateOnly
if ($lua.LuaScript -ne (Join-Path $assetRoot 'braveliltoaster.lua')) { throw 'The linked Lua script did not resolve.' }

$run = [IO.Directory]::CreateDirectory((Join-Path $root ('BZMAG-' + [guid]::NewGuid().ToString('N')))).FullName
$prepared = [IO.Directory]::CreateDirectory((Join-Path $run 'game/snapshot')).FullName
foreach ($item in Get-ChildItem -LiteralPath $map -File) { Copy-Item -LiteralPath $item.FullName -Destination $prepared }
$result = Join-Path $run 'launch.json'
$preparedMission = Join-Path $prepared 'braveliltoaster.bzn'
Expect-Refusal 'Missing Lua mission script' { & $launcher @common -Mission $preparedMission -PreparedRun $run -WaitForGame -ResultFile $result }
if ([IO.Directory]::Exists((Join-Path $run 'game')) -or (Get-Content -LiteralPath $result -Raw | ConvertFrom-Json).error -notlike 'Missing Lua mission script*') {
    throw 'The editor launch path failed to return a dependency error and clear its private snapshot.'
}

# A non-ValidateOnly launch must be refused when the compatibility contract is
# not READY, even when the embedded DLL identity verifies exactly.
$unverifiedMission = Join-Path $root 'plgr-stock/plgr.bzn'
if (Test-Path -LiteralPath $unverifiedMission -PathType Leaf) {
    Expect-Refusal 'compatibility validation [MISSION_UNVERIFIED' {
        & $launcher @common -Mission $unverifiedMission -ModProfile stock -MissionProfile custom-dll
    }
}
# Exercise the real preparation path and stop at the process boundary.
function Get-Process {
    [CmdletBinding()]
    param([string] $Name)
    if ($Name -eq 'steam') { [pscustomobject]@{ Name = 'test-steam' } }
}
function Start-Process {
    [CmdletBinding()]
    param([string] $FilePath, [string] $WorkingDirectory, [string] $ArgumentList, [string] $WindowStyle, [switch] $PassThru)
    if ((Split-Path -Leaf $FilePath) -ne 'battlezone2.exe') {
        Microsoft.PowerShell.Management\Start-Process @PSBoundParameters
        return
    }
    $config = [IO.File]::ReadAllText((Join-Path $WorkingDirectory 'bzmag.cfg'))
    if ($config.IndexOf('@rootdir\snapshot') -lt 0 -or $config.IndexOf('@rootdir\linkedassets\assets-0') -le $config.IndexOf('@rootdir\snapshot') -or
        -not (Test-Path -LiteralPath (Join-Path $WorkingDirectory 'Missions/LuaMission.dll')) -or
        -not (Test-Path -LiteralPath (Join-Path $WorkingDirectory 'snapshot/braveliltoaster.lua')) -or
        $ArgumentList -notmatch 'braveliltoaster\.bzn') {
        throw 'The launch did not stage the linked Lua mission and ordered resource streams.'
    }
    $process = [pscustomobject]@{ Id = 123; HasExited = $true; ExitCode = 0 }
    $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {}
    $process
}

Copy-Item -LiteralPath $lua.MissionDll -Destination (Join-Path $assetRoot 'LuaMission.dll')
$prepared = [IO.Directory]::CreateDirectory((Join-Path $run 'game/snapshot')).FullName
foreach ($item in Get-ChildItem -LiteralPath $map -File) { Copy-Item -LiteralPath $item.FullName -Destination $prepared }
$launch = & $launcher @common -Mission (Join-Path $prepared 'braveliltoaster.bzn') -PreparedRun $run -WaitForGame -AssetProfile $profile -ResultFile $result
if ($launch.ProcessId -ne 123 -or (Get-Content -LiteralPath $result -Raw | ConvertFrom-Json).ExitCode -ne 0 -or
    [IO.Directory]::Exists((Join-Path $run 'game')) -or -not (Test-Path -LiteralPath (Join-Path $assetRoot 'braveliltoaster.lua'))) {
    throw 'The prepared launch did not complete cleanly or touched its linked assets.'
}
"PASS: BZN admission, adapter requirements, linked DLL/Lua, and prepared launch through the process boundary ($root)"
