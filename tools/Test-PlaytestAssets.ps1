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
if ($native.LaunchRoute -ne 'native' -or $stock.LaunchRoute -ne 'convert') {
    throw 'Verified BZN layouts did not select their expected launch routes.'
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
