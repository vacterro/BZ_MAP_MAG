$script:PlaytestAssetIndexMemoryCache = @{}

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

function Get-ExplicitAssetRoots([string[]] $AssetRoots) {
    if (-not $AssetRoots) { return }
    $seen = @{}
    foreach ($entry in $AssetRoots) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $root = Get-Item -LiteralPath $entry -ErrorAction SilentlyContinue
        if (-not $root -or -not $root.PSIsContainer) { throw "Asset root folder was not found: $entry" }
        $resolved = (Resolve-Path -LiteralPath $root.FullName).Path
        if (-not $seen.ContainsKey($resolved)) {
            $seen[$resolved] = $true
            $resolved
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

function Get-WorkshopAssetFolders([string] $Game, [string] $ModProfile) {
    if (-not $ModProfile -or $ModProfile -ieq 'stock') { return }
    $wsRoot = [IO.Path]::GetFullPath((Join-Path $Game '../../workshop/content/624970'))
    if (-not (Test-Path -LiteralPath $wsRoot -PathType Container)) { return }
    $targetId = switch ($ModProfile.ToLowerInvariant()) {
        'vsr' { '1325933293' }
        'vrv' { '3820486276' }
        default {
            if ($ModProfile -match '^(?:custom:ws-)?(\d+)$') { $Matches[1] } else { '' }
        }
    }
    if (-not $targetId) { return }
    $itemDir = Join-Path $wsRoot $targetId
    if (-not (Test-Path -LiteralPath $itemDir -PathType Container)) { return }
    $seen = @{}
    $queue = [System.Collections.Generic.List[string]]::new()
    $queue.Add((Resolve-Path -LiteralPath $itemDir).Path)
    $seen[$queue[0]] = $true
    if ($ModProfile -ieq 'vrv') {
        $vsrDir = Join-Path $wsRoot '1325933293'
        if (Test-Path -LiteralPath $vsrDir -PathType Container) {
            $r = (Resolve-Path -LiteralPath $vsrDir).Path
            if (-not $seen.ContainsKey($r)) { $seen[$r] = $true; $queue.Add($r) }
        }
    }
    $ini = Get-ChildItem -LiteralPath $itemDir -Filter '*.ini' -File | Select-Object -First 1
    if ($ini) {
        $text = [IO.File]::ReadAllText($ini.FullName)
        $m = [regex]::Match($text, '(?im)^\s*assetDependencies\s*=\s*"?([^"\r\n]+)')
        if ($m.Success) {
            foreach ($tok in ($m.Groups[1].Value -split ',')) {
                $depId = $tok.Trim()
                if ($depId -match '^\d+$') {
                    $depDir = Join-Path $wsRoot $depId
                    if (Test-Path -LiteralPath $depDir -PathType Container) {
                        $r = (Resolve-Path -LiteralPath $depDir).Path
                        if (-not $seen.ContainsKey($r)) { $seen[$r] = $true; $queue.Add($r) }
                    }
                }
            }
        }
    }
    return @($queue.ToArray())
}

function Get-PlaytestAssetConfiguration([string] $Game, [string] $Mission, [string] $AssetProfile, [string] $VrvSource, [string[]] $AssetRoots = @(), [string] $ModProfile = '', [string] $Converter = '') {
    $converterSource = if ($Converter) { $Converter } elseif ($VrvSource) { $VrvSource } else { '' }
    $converterRoot = if ($converterSource) { (Resolve-Path -LiteralPath $converterSource).Path } else { '' }
    $linked = @(Get-LinkedAssetFolders $AssetProfile)
    $explicit = @(Get-ExplicitAssetRoots $AssetRoots)
    # Strict Stock isolation: when -ModProfile 'stock' is selected, NEVER mount
    # VRV or VSR folders even if a format converter is configured.
    $modFolders = @()
    $vrv = @()
    if ($ModProfile) {
        if ($ModProfile -ine 'stock') {
            $modFolders = @(Get-WorkshopAssetFolders $Game $ModProfile)
            if ($ModProfile -ieq 'vrv' -and $modFolders.Count -eq 0 -and $VrvSource) {
                $vrv = @(Get-VrvAssetFolders $Game $VrvSource)
            }
        }
    } else {
        # Legacy callers without -ModProfile retain backward-compatible -VrvSource asset behavior.
        $vrv = @(Get-VrvAssetFolders $Game $VrvSource)
    }
    $combined = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($folder in ($linked + $explicit + $modFolders + $vrv)) {
        if ($folder -and -not $seen.ContainsKey($folder)) {
            $seen[$folder] = $true
            $combined.Add($folder)
        }
    }
    $nativeRoots = @()
    foreach ($sub in 'bz2r_res','bz2r_loc') {
        $candidate = Join-Path $Game $sub
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $nativeRoots += (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return [pscustomobject]@{
        ModProfile = $ModProfile
        ConverterRoot = $converterRoot
        LinkedFolders = $linked
        ExplicitAssetRoots = $explicit
        ModFolders = $modFolders
        VrvFolders = $vrv
        AssetRoots = @($combined.ToArray())
        NativeRoots = $nativeRoots
        MissionFolder = (Split-Path -Parent $Mission)
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

function Get-AssetCacheDirectory([string] $CacheRoot) {
    if ($CacheRoot) { return $CacheRoot }
    return (Join-Path ([IO.Path]::GetTempPath()) 'bzmag-asset-cache')
}

function Get-StringSha256([string] $Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-AssetRootStamp([string] $Root, [bool] $Recurse = $true) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return 'missing' }
    $parts = [System.Collections.Generic.List[string]]::new()
    $rootItem = [IO.DirectoryInfo]::new($Root)
    $parts.Add("root:$($rootItem.LastWriteTimeUtc.Ticks)")
    if ($Recurse) {
        foreach ($dirPath in ([IO.Directory]::EnumerateDirectories($Root, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)) {
            $dirInfo = [IO.DirectoryInfo]::new($dirPath)
            $parts.Add("d:$($dirPath.Substring($Root.Length)):$($dirInfo.LastWriteTimeUtc.Ticks)")
        }
    }
    $archOption = if ($Recurse) { [IO.SearchOption]::AllDirectories } else { [IO.SearchOption]::TopDirectoryOnly }
    foreach ($pakPath in ([IO.Directory]::EnumerateFiles($Root, '*.pak', $archOption) | Sort-Object)) {
        $arch = [IO.FileInfo]::new($pakPath)
        $parts.Add("p:$($pakPath.Substring($Root.Length)):$($arch.Length):$($arch.LastWriteTimeUtc.Ticks)")
    }
    return Get-StringSha256 ($parts -join '|')
}

function Get-DocpPakOdfEntries([string] $PakPath) {
    $entries = [System.Collections.Generic.List[string]]::new()
    $stream = [IO.File]::OpenRead($PakPath)
    $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::ASCII)
    try {
        if ($stream.Length -lt 32) { return $entries }
        $magic = $reader.ReadBytes(4)
        if ([Text.Encoding]::ASCII.GetString($magic) -ne 'DOCP') { return $entries }
        $ver = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        $count = $reader.ReadUInt32()
        $dirOffset = $reader.ReadUInt32()
        if ($ver -ne 2 -or $count -gt 65536 -or $dirOffset -ge $stream.Length) { return $entries }
        $stream.Position = [long]$dirOffset
        for ($i = 0; $i -lt $count -and $stream.Position + 5 -le $stream.Length; $i++) {
            $null = $reader.ReadUInt32()
            $nameLen = [int]$reader.ReadByte()
            if ($stream.Position + $nameLen + 12 -gt $stream.Length) { break }
            $name = [Text.Encoding]::ASCII.GetString($reader.ReadBytes($nameLen))
            $null = $reader.ReadBytes(12)
            if ($name.EndsWith('.odf', [StringComparison]::OrdinalIgnoreCase)) {
                $entries.Add("${PakPath}::${name}")
            }
        }
    } catch {
        # Corrupt or non-DOCP pak is treated as having no readable ODF directory.
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
    return $entries
}

function Build-AssetRootOdfIndex([string] $Root, [bool] $Recurse = $true) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $map }
    $searchOption = if ($Recurse) { [IO.SearchOption]::AllDirectories } else { [IO.SearchOption]::TopDirectoryOnly }
    foreach ($file in [IO.Directory]::EnumerateFiles($Root, '*.odf', $searchOption)) {
        $key = [IO.Path]::GetFileName($file).ToLowerInvariant()
        if (-not $map.ContainsKey($key)) { $map[$key] = [System.Collections.Generic.List[string]]::new() }
        $map[$key].Add($file)
    }
    foreach ($pak in [IO.Directory]::EnumerateFiles($Root, '*.pak', $searchOption)) {
        foreach ($entry in (Get-DocpPakOdfEntries $pak)) {
            $leaf = [IO.Path]::GetFileName($entry.Substring($entry.IndexOf('::') + 2)).ToLowerInvariant()
            if (-not $map.ContainsKey($leaf)) { $map[$leaf] = [System.Collections.Generic.List[string]]::new() }
            $map[$leaf].Add($entry)
        }
    }
    $result = @{}
    foreach ($k in $map.Keys) { $result[$k] = @($map[$k].ToArray()) }
    return $result
}

function Get-CachedAssetRootOdfIndex([string] $Root, [string] $CacheRoot, [ref] $CacheStats, [bool] $Recurse = $true, [bool] $BypassCache = $false) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @{} }
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    $stamp = Get-AssetRootStamp $resolved $Recurse
    if (-not $BypassCache) {
        if ($script:PlaytestAssetIndexMemoryCache.ContainsKey($resolved)) {
            $mem = $script:PlaytestAssetIndexMemoryCache[$resolved]
            if ($mem.Stamp -eq $stamp -and $mem.Recurse -eq $Recurse) {
                $CacheStats.Value.Hits++
                return $mem.Odfs
            }
        }
        $cacheDir = Get-AssetCacheDirectory $CacheRoot
        $cacheFile = Join-Path $cacheDir ((Get-StringSha256 "$resolved|$Recurse") + '.json')
        if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
            try {
                $disk = [IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json
                if ($disk.Version -eq 1 -and $disk.Root -eq $resolved -and $disk.Stamp -eq $stamp -and $disk.Odfs) {
                    $odfTable = @{}
                    foreach ($prop in $disk.Odfs.PSObject.Properties) {
                        $odfTable[$prop.Name] = @($prop.Value)
                    }
                    $script:PlaytestAssetIndexMemoryCache[$resolved] = [pscustomobject]@{ Stamp = $stamp; Recurse = $Recurse; Odfs = $odfTable }
                    $CacheStats.Value.Hits++
                    return $odfTable
                }
            } catch {
                # Corrupt cache entry falls through to rebuild.
            }
        }
    }
    if (-not $BypassCache) {
        $CacheStats.Value.Misses++
    }
    $built = Build-AssetRootOdfIndex $resolved $Recurse
    if (-not $BypassCache) {
        $script:PlaytestAssetIndexMemoryCache[$resolved] = [pscustomobject]@{ Stamp = $stamp; Recurse = $Recurse; Odfs = $built }
        try {
            $cacheDir = Get-AssetCacheDirectory $CacheRoot
            $null = [IO.Directory]::CreateDirectory($cacheDir)
            $cacheFile = Join-Path $cacheDir ((Get-StringSha256 "$resolved|$Recurse") + '.json')
            $stage = "$cacheFile.$([guid]::NewGuid().ToString('N')).tmp"
            $payload = @{ Version = 1; Root = $resolved; Stamp = $stamp; Odfs = $built } | ConvertTo-Json -Depth 4 -Compress
            [IO.File]::WriteAllText($stage, $payload, [Text.Encoding]::UTF8)
            if (Test-Path -LiteralPath $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force }
            [IO.File]::Move($stage, $cacheFile)
        } catch {
            # Cache write failure must not abort Playtest validation.
        }
    }
    return $built
}

function Resolve-PlaytestOdfDependencies([string[]] $Odfs, [psobject] $Config, [string] $Game, [string] $CacheRoot = '') {
    $required = @($Odfs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $cacheStats = [pscustomobject]@{ Hits = 0; Misses = 0 }
    $resolved = @{}
    $missing = [System.Collections.Generic.List[string]]::new()
    $ambiguous = [System.Collections.Generic.List[psobject]]::new()
    if ($required.Count -eq 0) {
        return [pscustomobject]@{
            RequiredOdfs = @()
            ResolvedOdfs = $resolved
            MissingOdfs = @()
            AmbiguousOdfs = @()
            CacheHits = 0
            CacheMisses = 0
        }
    }
    $rootEntries = [System.Collections.Generic.List[psobject]]::new()
    # Mission snapshot folder is small and mutable; scan fresh without persistent cache.
    $rootEntries.Add([pscustomobject]@{
        Root = $Config.MissionFolder
        Index = (Get-CachedAssetRootOdfIndex $Config.MissionFolder $CacheRoot ([ref]$cacheStats) $true $true)
    })
    foreach ($root in ($Config.AssetRoots + $Config.NativeRoots)) {
        $rootEntries.Add([pscustomobject]@{
            Root = $root
            Index = (Get-CachedAssetRootOdfIndex $root $CacheRoot ([ref]$cacheStats) $true $false)
        })
    }
    if (Test-Path -LiteralPath $Game -PathType Container) {
        $rootEntries.Add([pscustomobject]@{
            Root = $Game
            Index = (Get-CachedAssetRootOdfIndex $Game $CacheRoot ([ref]$cacheStats) $false $false)
        })
    }
    foreach ($odf in $required) {
        $key = $odf.ToLowerInvariant()
        $winner = $null
        foreach ($entry in $rootEntries) {
            if ($entry.Index.ContainsKey($key)) {
                $hits = @($entry.Index[$key])
                if ($hits.Count -gt 1) {
                    $ambiguous.Add([pscustomobject]@{ Odf = $odf; Root = $entry.Root; Matches = $hits })
                }
                if (-not $winner -and $hits.Count -ge 1) {
                    $winner = $hits[0]
                }
            }
        }
        if ($winner) {
            $resolved[$odf] = $winner
        } else {
            $missing.Add($odf)
        }
    }
    return [pscustomobject]@{
        RequiredOdfs = $required
        ResolvedOdfs = $resolved
        MissingOdfs = @($missing.ToArray())
        AmbiguousOdfs = @($ambiguous.ToArray())
        CacheHits = $cacheStats.Hits
        CacheMisses = $cacheStats.Misses
    }
}

function Get-PlaytestAssetPlan([string] $Game, [string] $Mission, [string] $AssetProfile, [string] $VrvSource, [bool] $SkipScripts, [string[]] $AssetRoots = @(), [string[]] $Odfs = @(), [string] $CacheRoot = '', [string] $ModProfile = '', [string] $Converter = '') {
    $config = Get-PlaytestAssetConfiguration $Game $Mission $AssetProfile $VrvSource $AssetRoots $ModProfile $Converter
    $plan = [pscustomobject]@{
        ModProfile = $config.ModProfile
        ConverterRoot = $config.ConverterRoot
        LinkedFolders = $config.LinkedFolders
        ExplicitAssetRoots = $config.ExplicitAssetRoots
        ModFolders = $config.ModFolders
        VrvFolders = $config.VrvFolders
        AssetRoots = $config.AssetRoots
        ScriptCheck = 'disabled'
        MissionDll = ''
        LuaScript = ''
        RequiredOdfs = @()
        ResolvedOdfs = @{}
        MissingOdfs = @()
        AmbiguousOdfs = @()
        CacheHits = 0
        CacheMisses = 0
    }
    if (-not $SkipScripts) {
        $dll = Get-NativeMissionDll $Mission
        $plan.ScriptCheck = 'unidentified'
        if ($dll) {
            $roots = @($config.MissionFolder) + @($config.AssetRoots) + @((Join-Path $Game 'Missions')) + @($config.NativeRoots)
            $plan.MissionDll = Find-PlaytestAsset $dll $roots
            if (-not $plan.MissionDll) { throw "Missing mission DLL $dll. Put it beside the map or link its folder in the asset profile." }
            if ($dll -ieq 'LuaMission.dll') {
                $name = [IO.Path]::GetFileNameWithoutExtension($Mission) + '.lua'
                $plan.LuaScript = Find-PlaytestAsset $name $roots
                if (-not $plan.LuaScript) { throw "Missing Lua mission script $name. Put it beside the map or link its folder in the asset profile." }
            }
            $plan.ScriptCheck = 'resolved'
        }
    }
    if ($Odfs -and $Odfs.Count -gt 0) {
        $odfReport = Resolve-PlaytestOdfDependencies $Odfs $config $Game $CacheRoot
        $plan.RequiredOdfs = $odfReport.RequiredOdfs
        $plan.ResolvedOdfs = $odfReport.ResolvedOdfs
        $plan.MissingOdfs = $odfReport.MissingOdfs
        $plan.AmbiguousOdfs = $odfReport.AmbiguousOdfs
        $plan.CacheHits = $odfReport.CacheHits
        $plan.CacheMisses = $odfReport.CacheMisses
        if ($plan.MissingOdfs.Count -gt 0) {
            throw "Missing object ODF dependencies: $($plan.MissingOdfs -join ', '). Link the required asset folder via -AssetProfile, -AssetRoots, or -VrvSource."
        }
    }
    return $plan
}