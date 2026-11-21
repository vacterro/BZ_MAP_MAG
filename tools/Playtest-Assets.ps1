function Get-LinkedAssetFolders([string] $AssetProfile) {
    if (-not $AssetProfile) { return }
    $profileFile = Get-Item -LiteralPath $AssetProfile
    if ($profileFile.PSIsContainer -or $profileFile.Length -gt 65536) { throw 'Expected a small JSON asset profile file.' }
    try {
        $profile = [IO.File]::ReadAllText($profileFile.FullName) | ConvertFrom-Json
    } catch {
        throw "Cannot read asset profile JSON: $($profileFile.FullName)"
    }
    if ($profile.folders -isnot [array]) {
        throw 'Asset profile must contain a folders array.'
    }
    $seen = @{}
    foreach ($entry in $profile.folders) {
        if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) { throw 'Asset profile folder paths must be nonempty strings.' }
        $path = if ([IO.Path]::IsPathRooted($entry)) { $entry } else { Join-Path $profileFile.DirectoryName $entry }
        $root = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $root -or -not $root.PSIsContainer) { throw "Asset profile folder was not found: $path" }
        if (-not $seen.ContainsKey($root.FullName)) {
            $seen[$root.FullName] = $true
            $root.FullName
        }
    }
}

function Get-VrvAssetFolders([string] $Game, [string] $VrvSource) {
    if (-not $VrvSource) { return }
    $deps = Join-Path $Game 'VRV/deps'
    foreach ($name in 'VSR','3532748119','1329659846','2785557433','2785542655','2814914461','2049956570','3493379153','2467249743') {
        $path = Join-Path $deps $name
        if (Test-Path -LiteralPath $path -PathType Container) { (Resolve-Path -LiteralPath $path).Path }
    }
}

function Get-NativeMissionDll([string] $Mission) {
    $file = Get-Item -LiteralPath $Mission
    if ($file.Length -gt 16MB) { return }
    $content = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($file.FullName))
    $header = [regex]::Match($content, '\Aversion\s+\[1\]\s*=\s*(?<version>\d+)[\r\n]+saveType\s+\[1\]\s*=\s*0[\r\n]+binarySave\s+\[1\]\s*=\s*(?<binary>true|false)[\r\n]+', 'IgnoreCase')
    if (-not $header.Success) { return }
    $records = @()
    if ($header.Groups['binary'].Value -ieq 'false') {
        $records = [regex]::Matches($content, '(?im)^dllName\s*=[ \t]*(?<name>[^\r\n]*)')
    } elseif ([int]$header.Groups['version'].Value -gt 1165) {
        # The BZ2 binary map stores the mission name after the 640-byte groupTargets frame.
        $records = [regex]::Matches($content, '\x00\x80\x02[\s\S]{640}\x02\x01\x00(?<len>[\x01-\x7F])\x02\k<len>\x00(?<name>[ -~]{1,127})\x04\x04\x00') |
            Where-Object { $_.Groups['name'].Length -eq [int][char]$_.Groups['len'].Value[0] }
    }
    $records = @($records | Where-Object { $_ -ne $null })
    if ($records.Count -gt 1) { throw 'The BZN contains multiple candidate mission DLL references.' }
    if ($records.Count -eq 1) {
        $name = $records[0].Groups['name'].Value.Trim().Trim('"')
        if ($name -and $name -notmatch '^[A-Za-z0-9_][A-Za-z0-9_. -]*\.dll$') { throw "Unsupported mission DLL name: $name" }
        $name
    }
}

function Find-PlaytestAsset([string] $Name, [string[]] $Roots) {
    foreach ($root in $Roots) {
        $path = Join-Path $root $Name
        if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-Item -LiteralPath $path).FullName }
        if (Test-Path -LiteralPath $root -PathType Container) {
            $found = Get-ChildItem -LiteralPath $root -Filter $Name -File -Recurse | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    }
}

function Get-PlaytestAssetPlan([string] $Game, [string] $Mission, [string] $AssetProfile, [string] $VrvSource, [bool] $SkipScripts) {
    $linked = @(Get-LinkedAssetFolders $AssetProfile)
    $vrv = @(Get-VrvAssetFolders $Game $VrvSource)
    $plan = [pscustomobject]@{ LinkedFolders = $linked; VrvFolders = $vrv; ScriptCheck = 'disabled'; MissionDll = ''; LuaScript = '' }
    if ($SkipScripts) { return $plan }
    $dll = Get-NativeMissionDll $Mission
    $plan.ScriptCheck = 'unidentified'
    if (-not $dll) { return $plan }
    $roots = @((Split-Path -Parent $Mission)) + $linked + $vrv + @((Join-Path $Game 'Missions'), (Join-Path $Game 'bz2r_res'), (Join-Path $Game 'bz2r_loc'))
    $plan.MissionDll = Find-PlaytestAsset $dll $roots
    if (-not $plan.MissionDll) { throw "Missing mission DLL $dll. Put it beside the map or link its folder in the asset profile." }
    if ($dll -ieq 'LuaMission.dll') {
        $name = [IO.Path]::GetFileNameWithoutExtension($Mission) + '.lua'
        $plan.LuaScript = Find-PlaytestAsset $name $roots
        if (-not $plan.LuaScript) { throw "Missing Lua mission script $name. Put it beside the map or link its folder in the asset profile." }
    }
    $plan.ScriptCheck = 'resolved'
    return $plan
}
