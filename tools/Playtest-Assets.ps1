$script:PlaytestAssetIndexMemoryCache = @{}

function Get-BzmagAppSourceDigest([string] $AppDir) {
    if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) { return '' }
    $resolvedApp = (Resolve-Path -LiteralPath $AppDir).Path.TrimEnd('\','/')
    $allowedExts = @('.gd','.tscn','.gdshader','.godot','.cfg','.ttf','.import')
    $files = Get-ChildItem -LiteralPath $resolvedApp -Recurse -File | Where-Object {
        $rel = $_.FullName.Substring($resolvedApp.Length + 1).Replace('\','/')
        (-not $rel.StartsWith('.godot/')) -and (-not $rel.StartsWith('tests/')) -and ($_.Extension.ToLowerInvariant() -in $allowedExts)
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($resolvedApp.Length + 1).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $parts.Add("${rel}:${hash}")
    }
    $parts.Sort([StringComparer]::Ordinal)
    return Get-StringSha256 ($parts -join "`n")
}

function Get-BzmagImportDigest([string] $AppDir) {
    if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) { return '' }
    $resolvedApp = (Resolve-Path -LiteralPath $AppDir).Path.TrimEnd('\','/')
    $files = Get-ChildItem -LiteralPath $resolvedApp -Recurse -File -Filter '*.import' | Where-Object {
        $rel = $_.FullName.Substring($resolvedApp.Length + 1).Replace('\','/')
        -not $rel.StartsWith('.godot/')
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($resolvedApp.Length + 1).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $parts.Add("${rel}:${hash}")
    }
    $parts.Sort([StringComparer]::Ordinal)
    return Get-StringSha256 ($parts -join "`n")
}

function Get-BzmagHelperProvenance([string] $RepoRoot) {
    $resolved = (Resolve-Path -LiteralPath $RepoRoot).Path
    $helpers = [ordered]@{}
    $parts = [System.Collections.Generic.List[string]]::new()
    $helperList = @(
        'tools/Start-Playtest.ps1',
        'tools/Playtest-Assets.ps1',
        'tools/Run-Ownership.ps1',
        'tools/Find-Bzcc.ps1',
        'tools/New-FlatTerrainSnapshot.ps1'
    )
    foreach ($rel in $helperList) {
        $full = Join-Path $resolved $rel
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            $h = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
            $helpers[$rel] = $h
            $parts.Add("${rel}:${h}")
        }
    }
    $previewRel = ''
    $previewBuilt = Join-Path $resolved 'build/object-preview/mesh-preview.exe'
    $previewBundled = Join-Path $resolved 'tools/mesh-preview.exe'
    if (Test-Path -LiteralPath $previewBuilt -PathType Leaf) {
        $previewRel = 'mesh-preview.exe'
        $h = (Get-FileHash -LiteralPath $previewBuilt -Algorithm SHA256).Hash.ToLowerInvariant()
        $helpers[$previewRel] = $h
        $parts.Add("${previewRel}:${h}")
    } elseif (Test-Path -LiteralPath $previewBundled -PathType Leaf) {
        $previewRel = 'mesh-preview.exe'
        $h = (Get-FileHash -LiteralPath $previewBundled -Algorithm SHA256).Hash.ToLowerInvariant()
        $helpers[$previewRel] = $h
        $parts.Add("${previewRel}:${h}")
    }
    return [pscustomobject]@{
        Helpers = $helpers
        Digest = if ($parts.Count -gt 0) { Get-StringSha256 ($parts -join "`n") } else { '' }
    }
}

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
    foreach ($raw in $AssetRoots) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $entries = if (Test-Path -LiteralPath $raw -PathType Container) { @($raw) } else { @($raw -split ';') }
        foreach ($entry in $entries) {
            $trimmed = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            $root = Get-Item -LiteralPath $trimmed -ErrorAction SilentlyContinue
            if (-not $root -or -not $root.PSIsContainer) { throw "Asset root folder was not found: $trimmed" }
            $resolved = (Resolve-Path -LiteralPath $root.FullName).Path
            if (-not $seen.ContainsKey($resolved)) {
                $seen[$resolved] = $true
                $resolved
            }
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

$script:KnownDllSignatures = @{
    '415ad6ca656c02972ff5b88c574d51cb508f6574001b848b84c30b776d9b1bc2' = @{ Mod = 'stock'; Name = 'Strategy02.dll'; Mission = 'strategy' }
    'c3dc76d348ef8a31cfade7b3928e0f650d4bfb62348942177e1bc364470c65ce' = @{ Mod = 'stock'; Name = 'Instant.dll'; Mission = 'instant' }
    '62f296053c99bb5b871e17b5140ac3b53f75ce6442721219c581611fad9439fc' = @{ Mod = 'stock'; Name = 'mpinstant.dll'; Mission = 'mpi' }
    '20344ce75d291e68e95692d8b6202b7f7d3ae08c93a3664907d65ec987071046' = @{ Mod = 'stock'; Name = 'deathmatch01.dll'; Mission = 'duel' }
    '687c1ed92f6eaee882a688f78f75eb7be8972e3f7590db0fc9b0b53e8c56eec6' = @{ Mod = 'stock'; Name = 'StratCTF.dll'; Mission = 'strategy' }
    'b197f15b12901c9d87a0b80a7b775860a15302320cd33f1b09fa2b8683da57db' = @{ Mod = 'stock'; Name = 'LuaMission.dll'; Mission = 'lua' }
    'a4b3ce223fc305df88507b07d1e0790ced781df5147ccce4886d776c45c0b6bb' = @{ Mod = 'vsr';   Name = 'Strategy02.dll'; Mission = 'strategy' }
    'c17c7d1c7fa7a75b87f3350f3b66599e207e9ece580d555b5c7c5051bd7e407d' = @{ Mod = 'vsr';   Name = 'Instant.dll'; Mission = 'instant' }
    'b982c41694aba3e7d48fe4bc2d145d6d4f0261d529dea17d644212478c5e6020' = @{ Mod = 'vsr';   Name = 'deathmatch01.dll'; Mission = 'duel' }
    'a7097e937761f2ef81d84693ef537c0102cc359ad3d6a7aa1d7d01a6b98a5a2a' = @{ Mod = 'vsr';   Name = 'LuaMission.dll'; Mission = 'lua' }
    'afc99de3250ab37dccfbaf099b4983a7a402c0f8ae8d535f63fac7f91297a989' = @{ Mod = 'vrv';   Name = 'Strategy02.dll'; Mission = 'strategy' }
    '8879f1e83d507720774d48c196a0f750b40044ad3c80c279ff348436edb79c0d' = @{ Mod = 'vrv';   Name = 'Instant.dll'; Mission = 'instant' }
    'f7759194b4798120ed87525cd27c4e6574454fdb2eb67d58cc33cd47a9e79834' = @{ Mod = 'vrv';   Name = 'mpinstant.dll'; Mission = 'mpi' }
    'd09c8bfc1e4a71723185e0ebf5f2cb1f4c88821e726396eaa43d45a7743dcd4a' = @{ Mod = 'vrv';   Name = 'deathmatch01.dll'; Mission = 'duel' }
    'e3f6e4b5062cfced01f70f81809b83d7bbed1fb9f4ab563b33257fc015fa0130' = @{ Mod = 'vrv';   Name = 'StratCTF.dll'; Mission = 'strategy' }
    '65e575b840c5840ebc7df8b21ee35c116c1fd88abe63528be9483f0dbf115d11' = @{ Mod = 'vrv';   Name = 'VrvPrepare.dll'; Mission = 'custom-dll' }
}

$script:ExplicitDllInheritance = @{
    'vsr' = @{ 'mpinstant.dll' = 'stock'; 'stratctf.dll' = 'stock' }
    'vrv' = @{ 'luamission.dll' = 'stock' }
}

$script:MissionCanonicalDll = @{
    'strategy' = 'Strategy02.dll'
    'instant'  = 'Instant.dll'
    'mpi'      = 'mpinstant.dll'
    'duel'     = 'deathmatch01.dll'
    'lua'      = 'LuaMission.dll'
}

function Get-ExpectedMissionDll([string] $MissionProfile = '', [string] $ModProfile = '') {
    $mis = if ($MissionProfile) { $MissionProfile.Trim().ToLowerInvariant() } else { '' }
    if ($script:MissionCanonicalDll.ContainsKey($mis)) {
        return $script:MissionCanonicalDll[$mis]
    }
    return ''
}

function Get-DllIdentityInfo([string] $DllPath, [string] $ModProfile = '', [string] $ExpectedDll = '', [string] $MissionProfile = '', [string] $ActualBznDll = '__UNSET__') {
    $tgt = if ($ModProfile) { $ModProfile.Trim().ToLowerInvariant() } else { '' }
    $mis = if ($MissionProfile) { $MissionProfile.Trim().ToLowerInvariant() } else { '' }
    $exp = if ($ExpectedDll) { $ExpectedDll.Trim() } elseif ($mis -and $script:MissionCanonicalDll.ContainsKey($mis)) { $script:MissionCanonicalDll[$mis] } else { '' }
    $leaf = if ($DllPath) { Split-Path -Leaf $DllPath } else { '' }
    $actualRef = if ($ActualBznDll -eq '__UNSET__') { $leaf } else { $ActualBznDll.Trim() }

    $missionMismatch = $false
    $missionMismatchReason = ''
    if ($exp) {
        if (-not $actualRef) {
            $missionMismatch = $true
            $missionMismatchReason = "BZN embeds no mission DLL, but mission profile '$mis' requires '$exp'."
        } elseif ($actualRef -ine $exp) {
            $missionMismatch = $true
            $missionMismatchReason = "BZN embeds mission DLL '$actualRef', contradicting mission profile '$mis' which expects '$exp'."
        }
    } elseif ($mis -eq 'blank' -and $actualRef) {
        $missionMismatch = $true
        $missionMismatchReason = "BZN embeds mission DLL '$actualRef', contradicting 'blank' mission profile."
    }

    if (-not $DllPath -or -not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
        $st = if ($missionMismatch -and -not $actualRef) { 'MISSION_PROFILE_MISMATCH' } else { 'MISSING' }
        $det = if ($missionMismatch -and -not $actualRef) { $missionMismatchReason } else { "Mission DLL was not found." }
        return [pscustomobject]@{
            Path = ''; Requested = $leaf; ActualBznDll = $actualRef; Expected = $exp; MissionProfile = $mis; TargetMod = $tgt
            CanonicalName = ''; Sha256 = ''; SizeBytes = 0; MatchedMod = ''; Verified = $false; KnownSignature = $false
            SemanticState = 'UNKNOWN'; Status = $st; Detail = $det
        }
    }
    # Always hash live bytes on disk; never rely on cached DLL identity.
    $sha = (Get-FileHash -LiteralPath $DllPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $size = (Get-Item -LiteralPath $DllPath).Length
    $sig = $script:KnownDllSignatures[$sha]
    $matched = if ($sig) { $sig.Mod } else { 'unknown' }
    $canonical = if ($sig) { $sig.Name } else { '' }
    $known = [bool]($null -ne $sig)

    $status = 'HASH_UNVERIFIED'
    $verified = $false
    $sem = 'UNKNOWN'
    $detail = ''

    if (-not $known) {
        if ($missionMismatch) {
            $status = 'MISSION_PROFILE_MISMATCH'
            $sem = 'MISMATCH'
            $detail = "$missionMismatchReason (resolved '$leaf', unverified SHA-256 $($sha.Substring(0,12)))."
        } else {
            $status = 'HASH_UNVERIFIED'
            $sem = 'UNKNOWN'
            $detail = "Mission DLL '$leaf' ($($sha.Substring(0,12))) does not match any verified signature; semantics are UNKNOWN."
        }
    } elseif ($canonical -ine $leaf) {
        $status = 'DLL_NAME_MISMATCH'
        $sem = 'MISMATCH'
        $detail = "DLL name mismatch: '$leaf' carries the SHA-256 of $($matched.ToUpperInvariant()) '$canonical' ($($sha.Substring(0,12)))."
    } elseif ($missionMismatch) {
        $status = 'MISSION_PROFILE_MISMATCH'
        $sem = 'MISMATCH'
        $detail = "$missionMismatchReason (file '$leaf' is $($matched.ToUpperInvariant()) '$canonical')."
    } elseif ($exp -and $canonical -ine $exp) {
        $status = 'MISSION_PROFILE_MISMATCH'
        $sem = 'MISMATCH'
        $detail = "Mission contract mismatch: resolved '$canonical', expected '$exp'."
    } elseif (-not $tgt) {
        $status = 'VERIFIED_EXACT'
        $verified = $true
        $sem = 'VERIFIED'
        $detail = "Exact $($matched.ToUpperInvariant()) '$canonical' SHA-256 verified ($($sha.Substring(0,12)))."
    } elseif ($tgt -in 'stock','vsr','vrv') {
        if ($matched -eq $tgt) {
            $status = 'VERIFIED_EXACT'
            $verified = $true
            $sem = 'VERIFIED'
            $detail = "Exact $($tgt.ToUpperInvariant()) '$canonical' SHA-256 verified ($($sha.Substring(0,12)))."
        } else {
            $inhMap = $script:ExplicitDllInheritance[$tgt]
            $allowedParent = if ($inhMap) { $inhMap[$canonical.ToLowerInvariant()] } else { '' }
            if ($allowedParent -and $matched -eq $allowedParent) {
                $status = 'VERIFIED_EXPLICIT_INHERITANCE'
                $verified = $true
                $sem = 'VERIFIED'
                $detail = "Explicitly inherited $($allowedParent.ToUpperInvariant()) '$canonical' for $($tgt.ToUpperInvariant()) verified ($($sha.Substring(0,12)))."
            } else {
                $status = 'HASH_MISMATCH'
                $sem = 'MISMATCH'
                $detail = "Mod DLL hash mismatch: '$canonical' belongs to $($matched.ToUpperInvariant()) ($($sha.Substring(0,12))), not target mod $($tgt.ToUpperInvariant())."
            }
        }
    } else {
        if ($matched -eq 'stock') {
            $status = 'VERIFIED_EXPLICIT_INHERITANCE'
            $verified = $true
            $sem = 'VERIFIED'
            $detail = "Custom mod '$tgt' explicitly inherits verified Stock '$canonical' ($($sha.Substring(0,12)))."
        } else {
            $status = 'HASH_MISMATCH'
            $sem = 'MISMATCH'
            $detail = "Custom mod '$tgt' resolved $($matched.ToUpperInvariant()) '$canonical' without verified inheritance."
        }
    }

    return [pscustomobject]@{
        Path = $DllPath; Requested = $leaf; ActualBznDll = $actualRef; Expected = $exp; MissionProfile = $mis; TargetMod = $tgt
        CanonicalName = $canonical; Sha256 = $sha; SizeBytes = $size; MatchedMod = $matched; Verified = $verified
        KnownSignature = $known; SemanticState = $sem; Status = $status; Detail = $detail
    }
}

function Get-WorkshopDependencyGraph([string] $Game, [string] $ModProfile) {
    $result = [pscustomobject]@{ Roots = @(); MissingDependencies = @(); DependencyCycles = @() }
    if (-not $ModProfile -or $ModProfile -ieq 'stock') { return $result }
    $wsRoot = [IO.Path]::GetFullPath((Join-Path $Game '../../workshop/content/624970'))
    if (-not (Test-Path -LiteralPath $wsRoot -PathType Container)) { return $result }
    $targetId = switch ($ModProfile.ToLowerInvariant()) {
        'vsr' { '1325933293' }
        'vrv' { '3820486276' }
        default {
            if ($ModProfile -match '^(?:custom:ws-)?(\d+)$') { $Matches[1] } else { '' }
        }
    }
    if (-not $targetId) { return $result }
    $queue = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    $cycles = [System.Collections.Generic.List[string]]::new()
    $seenPath = @{}
    $visitState = @{} # id -> 1 visiting, 2 done

    $walk = {
        param([string] $id, [bool] $traverseIni)
        $itemDir = Join-Path $wsRoot $id
        if (-not (Test-Path -LiteralPath $itemDir -PathType Container)) {
            if (-not $missing.Contains($id)) { $missing.Add($id) }
            return
        }
        if ($visitState[$id] -eq 1) {
            if (-not $cycles.Contains("ws:$id")) { $cycles.Add("ws:$id") }
            return
        }
        if ($visitState[$id] -eq 2) { return }
        $visitState[$id] = 1
        $resolved = (Resolve-Path -LiteralPath $itemDir).Path
        if (-not $seenPath.ContainsKey($resolved)) {
            $seenPath[$resolved] = $true
            $queue.Add($resolved)
        }
        if ($traverseIni) {
            $ini = Get-ChildItem -LiteralPath $itemDir -Filter '*.ini' -File | Select-Object -First 1
            if ($ini) {
                $text = [IO.File]::ReadAllText($ini.FullName)
                foreach ($line in ($text -split "`r?`n")) {
                    $clean = ($line -split ';|//')[0].Trim()
                    if ($clean -match '^(?i)assetDependencies\s*=\s*"?([^"]+)"?$') {
                        foreach ($tok in ($Matches[1] -split ',')) {
                            $depId = $tok.Trim()
                            if ($depId -match '^\d+$') {
                                & $walk $depId $true
                            }
                        }
                    }
                }
            }
        }
        $visitState[$id] = 2
    }

    & $walk $targetId $true
    # VRV mounts VSR's own folder (1325933293) as its parent config mod without inheriting unrelated seasonal VSR map packs.
    if ($ModProfile -ieq 'vrv') {
        & $walk '1325933293' $false
    }
    $result.Roots = @($queue.ToArray())
    $result.MissingDependencies = @($missing.ToArray())
    $result.DependencyCycles = @($cycles.ToArray())
    return $result
}

function Get-WorkshopAssetFolders([string] $Game, [string] $ModProfile) {
    $graph = Get-WorkshopDependencyGraph $Game $ModProfile
    return @($graph.Roots)
}

function Get-PlaytestAssetConfiguration([string] $Game, [string] $Mission, [string] $AssetProfile, [string] $VrvSource, [string[]] $AssetRoots = @(), [string] $ModProfile = '', [string] $Converter = '') {
    $converterSource = if ($Converter) { $Converter } elseif ($VrvSource) { $VrvSource } else { '' }
    # Only resolve converterRoot when it actually exists; stale unused -VrvSource must NEVER crash a native Stock 1192 route.
    $converterRoot = if ($converterSource -and (Test-Path -LiteralPath $converterSource)) { (Resolve-Path -LiteralPath $converterSource).Path } else { '' }
    $linked = @(Get-LinkedAssetFolders $AssetProfile)
    $explicit = @(Get-ExplicitAssetRoots $AssetRoots)
    # Strict Stock isolation: when -ModProfile 'stock' is selected, NEVER mount
    # VRV or VSR folders even if a format converter is configured.
    $modFolders = @()
    $missingModDeps = @()
    $depCycles = @()
    $vrv = @()
    if ($ModProfile) {
        if ($ModProfile -ine 'stock') {
            $wsGraph = Get-WorkshopDependencyGraph $Game $ModProfile
            $modFolders = @($wsGraph.Roots)
            $missingModDeps = @($wsGraph.MissingDependencies)
            $depCycles = @($wsGraph.DependencyCycles)
            if ($ModProfile -in 'vsr','vrv' -and $VrvSource -and (Test-Path -LiteralPath $VrvSource)) {
                if ($modFolders.Count -eq 0) {
                    $vrv = @(Get-VrvAssetFolders $Game $VrvSource)
                } elseif ($missingModDeps.Count -gt 0) {
                    # Targeted local fallback only for specific missing Workshop IDs
                    $stillMissing = [System.Collections.Generic.List[string]]::new()
                    $extraVrv = [System.Collections.Generic.List[string]]::new()
                    $depsBase = Join-Path $Game 'VRV/deps'
                    foreach ($mid in $missingModDeps) {
                        $cand = Join-Path $depsBase $mid
                        if (Test-Path -LiteralPath $cand -PathType Container) {
                            $extraVrv.Add((Resolve-Path -LiteralPath $cand).Path)
                        } else {
                            $stillMissing.Add($mid)
                        }
                    }
                    $vrv = @($extraVrv.ToArray())
                    $missingModDeps = @($stillMissing.ToArray())
                }
            }
        }
    } else {
        # Legacy callers without -ModProfile retain backward-compatible -VrvSource asset behavior.
        if ($VrvSource -and (Test-Path -LiteralPath $VrvSource)) {
            $vrv = @(Get-VrvAssetFolders $Game $VrvSource)
        }
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
        MissingModDependencies = $missingModDeps
        DependencyCycles = $depCycles
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

$script:TrackedStampExtensions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($e in '.odf','.msh','.fbx','.xsi','.material','.dds','.tga','.png','.wav','.ogg','.dll','.lua','.aip','.pak') { [void]$script:TrackedStampExtensions.Add($e) }
$script:TargetedHashExtensions = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($e in '.odf','.material','.dll','.lua','.pak') { [void]$script:TargetedHashExtensions.Add($e) }

function Get-AssetRootStamp([string] $Root, [bool] $Recurse = $true) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return 'missing' }
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    $parts = [System.Collections.Generic.List[string]]::new()
    $rootItem = [IO.DirectoryInfo]::new($resolvedRoot)
    $parts.Add("root:$($resolvedRoot.ToLowerInvariant()):$($rootItem.LastWriteTimeUtc.Ticks)")
    if ($Recurse) {
        foreach ($dirPath in ([IO.Directory]::EnumerateDirectories($resolvedRoot, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)) {
            $dirInfo = [IO.DirectoryInfo]::new($dirPath)
            $parts.Add("d:$($dirPath.Substring($resolvedRoot.Length).Replace('\','/').ToLowerInvariant()):$($dirInfo.LastWriteTimeUtc.Ticks)")
        }
    }
    $searchOption = if ($Recurse) { [IO.SearchOption]::AllDirectories } else { [IO.SearchOption]::TopDirectoryOnly }
    $smallCandidates = [System.Collections.Generic.List[object]]::new()
    foreach ($filePath in ([IO.Directory]::EnumerateFiles($resolvedRoot, '*', $searchOption) | Sort-Object)) {
        $ext = [IO.Path]::GetExtension($filePath)
        if (-not $script:TrackedStampExtensions.Contains($ext)) { continue }
        $fi = [IO.FileInfo]::new($filePath)
        $rel = $filePath.Substring($resolvedRoot.Length).Replace('\','/').TrimStart('/').ToLowerInvariant()
        $entry = "f:${rel}:$($fi.Length):$($fi.LastWriteTimeUtc.Ticks)"
        if (($script:TargetedHashExtensions.Contains($ext) -and $fi.Length -le 262144) -or ($ext -ieq '.msh' -and $fi.Length -le 65536)) {
            $smallCandidates.Add([pscustomobject]@{ Path = $filePath; Rel = $rel })
        }
        $parts.Add($entry)
    }
    foreach ($cand in $smallCandidates) {
        $h = (Get-FileHash -LiteralPath $cand.Path -Algorithm SHA256).Hash.Substring(0, 16).ToLowerInvariant()
        $parts.Add("ch:$($cand.Rel)=$h")
    }
    return Get-StringSha256 ($parts -join '|')
}

function Get-DocpPakDirectory([string] $PakPath) {
    $res = [pscustomobject]@{
        Ok = $false; PakPath = $PakPath; Entries = @{}; EntryList = @()
        DuplicateEntries = @(); CorruptEntries = @(); Truncated = $false; Corrupt = $false; Error = ''
    }
    if (-not $PakPath -or -not (Test-Path -LiteralPath $PakPath -PathType Leaf)) {
        $res.Error = 'PAK missing.'; return $res
    }
    $stream = [IO.File]::OpenRead($PakPath)
    $reader = [IO.BinaryReader]::new($stream, [Text.Encoding]::ASCII)
    try {
        $total = $stream.Length
        if ($total -lt 32) { $res.Truncated = $true; $res.Corrupt = $true; $res.Error = 'Truncated DOCP header.'; return $res }
        $magic = [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        if ($magic -ne 'DOCP') { $res.Corrupt = $true; $res.Error = 'Not a DOCP archive.'; return $res }
        $ver = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        $null = $reader.ReadUInt32()
        $count = $reader.ReadUInt32()
        $dirOffset = $reader.ReadUInt32()
        if ($ver -ne 2 -or $count -gt 65536) { $res.Corrupt = $true; $res.Error = "Unsupported DOCP version/count ($ver/$count)."; return $res }
        if ($count -eq 0) { $res.Ok = $true; return $res }
        if ($dirOffset -lt 32 -or $dirOffset -ge $total) { $res.Truncated = $true; $res.Corrupt = $true; $res.Error = 'DOCP dirOffset out of bounds.'; return $res }
        $stream.Position = [long]$dirOffset
        $entries = @{}
        $list = [System.Collections.Generic.List[object]]::new()
        $dups = [System.Collections.Generic.List[string]]::new()
        $corrupts = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $count; $i++) {
            if ($stream.Position + 5 -gt $total) { $res.Truncated = $true; $res.Corrupt = $true; $res.Error = "Truncated directory at $i/$count."; break }
            $flags = $reader.ReadUInt32()
            $nameLen = [int]$reader.ReadByte()
            if ($nameLen -le 0 -or $stream.Position + $nameLen + 12 -gt $total) { $res.Truncated = $true; $res.Corrupt = $true; $res.Error = "Truncated entry $i."; break }
            $name = [Text.Encoding]::ASCII.GetString($reader.ReadBytes($nameLen))
            $offset = [long]$reader.ReadUInt32()
            $packedSize = [long]$reader.ReadUInt32()
            $unpackedSize = [long]$reader.ReadUInt32()
            $eCorrupt = $false; $eErr = ''
            $emptyStub = ($offset -eq 0 -and $packedSize -eq 0 -and $unpackedSize -eq 0)
            if ($name.Contains('..') -or $name.Contains(':') -or $name.StartsWith('/') -or $name.StartsWith('\')) {
                $eCorrupt = $true; $eErr = 'Unsafe entry name.'
            } elseif (-not $emptyStub) {
                if ($offset -lt 32 -or $offset -ge $total -or ($offset + $packedSize) -gt $total) { $eCorrupt = $true; $eErr = 'Entry offset/size out of bounds.' }
                elseif ($dirOffset -gt $offset -and ($offset + $packedSize) -gt $dirOffset) { $eCorrupt = $true; $eErr = 'Entry overlaps directory.' }
                elseif (($packedSize -eq 0 -and $unpackedSize -gt 0) -or ($unpackedSize -gt 0 -and $packedSize -gt ($unpackedSize + 1024 + [long]($unpackedSize / 16)))) { $eCorrupt = $true; $eErr = 'Invalid packed/unpacked sizes.' }
            }
            $leaf = [IO.Path]::GetFileName($name.Replace('\','/')).ToLowerInvariant()
            $meta = [pscustomobject]@{
                Name = $name; Leaf = $leaf; Flags = $flags; Offset = $offset; PackedSize = $packedSize; UnpackedSize = $unpackedSize
                Compressed = ((-not $emptyStub) -and ($packedSize -gt 0) -and ($packedSize -ne $unpackedSize))
                EmptyStub = $emptyStub; Oversized = ($unpackedSize -gt 4194304); Corrupt = $eCorrupt; Error = $eErr
                Provenance = "${PakPath}::${name}"
            }
            $list.Add($meta)
            if ($eCorrupt) { $corrupts.Add($meta) }
            if ($entries.ContainsKey($leaf)) {
                if (-not $dups.Contains($leaf)) { $dups.Add($leaf) }
                if ($entries[$leaf].Corrupt -and -not $eCorrupt) { $entries[$leaf] = $meta }
            } else {
                $entries[$leaf] = $meta
            }
        }
        $res.Entries = $entries
        $res.EntryList = @($list.ToArray())
        $res.DuplicateEntries = @($dups.ToArray())
        $res.CorruptEntries = @($corrupts.ToArray())
        $res.Ok = (-not $res.Truncated) -and ($list.Count -eq $count)
    } catch {
        $res.Corrupt = $true; $res.Error = $_.Exception.Message
    } finally {
        $reader.Dispose()
        $stream.Dispose()
    }
    return $res
}

function Read-DocpPakEntry([string] $PakPath, [string] $EntryName, [int] $MaxUnpacked = 262144) {
    $dir = Get-DocpPakDirectory $PakPath
    $leaf = [IO.Path]::GetFileName($EntryName.Replace('\','/')).ToLowerInvariant()
    if (-not $dir.Entries.ContainsKey($leaf)) {
        return [pscustomobject]@{ Ok = $false; Status = $(if ($dir.Corrupt) { 'ENTRY_CORRUPT' } else { 'MISSING' }); Bytes = [byte[]]@(); Error = $dir.Error }
    }
    $m = $dir.Entries[$leaf]
    if ($m.Corrupt) { return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = $m.Error } }
    if ($m.EmptyStub) { return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_INDEXED'; Bytes = [byte[]]@(); Error = 'Metadata-only / empty entry.' } }
    if ($m.UnpackedSize -gt [Math]::Min($MaxUnpacked, 4194304)) { return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_INDEXED'; Bytes = [byte[]]@(); Error = 'Oversized entry.' } }
    $stream = [IO.File]::OpenRead($PakPath)
    try {
        if ($m.Offset + $m.PackedSize -gt $stream.Length) { return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = 'Entry exceeds archive length.' } }
        $stream.Position = $m.Offset
        $raw = [byte[]]::new([int]$m.PackedSize)
        $read = $stream.Read($raw, 0, $raw.Length)
        if ($read -ne $raw.Length) { return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = 'Short read.' } }
        if (-not $m.Compressed) {
            # A stored entry may still carry a zlib wrapper when packedSize equals
            # unpackedSize; probe the RFC 1950 header like app/core/asset_index.gd
            # before trusting the raw bytes as readable content.
            if ($raw.Length -ge 6) {
                $zCmf = [int]$raw[0]
                $zFlg = [int]$raw[1]
                if ((($zCmf -band 0x0F) -eq 8) -and (((($zCmf -shl 8) -bor $zFlg) % 31) -eq 0)) {
                    $zIn = [IO.MemoryStream]::new($raw, 2, $raw.Length - 2)
                    $zDef = [IO.Compression.DeflateStream]::new($zIn, [IO.Compression.CompressionMode]::Decompress)
                    $zOut = [IO.MemoryStream]::new()
                    try {
                        $zDef.CopyTo($zOut)
                        $zBytes = $zOut.ToArray()
                        if ($zBytes.Length -eq $m.UnpackedSize) {
                            return [pscustomobject]@{ Ok = $true; Status = 'CONTENT_READABLE'; Bytes = $zBytes; Error = '' }
                        }
                        # A zlib-looking payload that does not decompress to the
                        # declared size is corrupt content, not readable raw bytes.
                        return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = 'Decompressed size mismatch.' }
                    } catch {
                        return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = $_.Exception.Message }
                    } finally {
                        $zDef.Dispose(); $zIn.Dispose(); $zOut.Dispose()
                    }
                }
            }
            return [pscustomobject]@{ Ok = $true; Status = 'CONTENT_READABLE'; Bytes = $raw; Error = '' }
        }
        $cmf = [int]$raw[0]
        $flg = [int]$raw[1]
        if ($raw.Length -lt 6 -or (($cmf -band 0x0F) -ne 8) -or (((($cmf -shl 8) -bor $flg) % 31) -ne 0)) {
            return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_INDEXED'; Bytes = [byte[]]@(); Error = 'Unsupported compression method.' }
        }
        $inMs = [IO.MemoryStream]::new($raw, 2, $raw.Length - 2)
        $def = [IO.Compression.DeflateStream]::new($inMs, [IO.Compression.CompressionMode]::Decompress)
        $outMs = [IO.MemoryStream]::new()
        try {
            $def.CopyTo($outMs)
            $outBytes = $outMs.ToArray()
            if ($outBytes.Length -ne $m.UnpackedSize) {
                return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = 'Decompressed size mismatch.' }
            }
            return [pscustomobject]@{ Ok = $true; Status = 'CONTENT_READABLE'; Bytes = $outBytes; Error = '' }
        } catch {
            return [pscustomobject]@{ Ok = $false; Status = 'ENTRY_CORRUPT'; Bytes = [byte[]]@(); Error = $_.Exception.Message }
        } finally {
            $def.Dispose(); $inMs.Dispose(); $outMs.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-DocpPakOdfEntries([string] $PakPath) {
    $entries = [System.Collections.Generic.List[string]]::new()
    $dir = Get-DocpPakDirectory $PakPath
    foreach ($m in $dir.EntryList) {
        if ($m.Name.EndsWith('.odf', [StringComparison]::OrdinalIgnoreCase)) {
            $entries.Add($m.Provenance)
        }
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

function Get-PlaytestAssetPlan([string] $Game, [string] $Mission, [string] $AssetProfile, [string] $VrvSource, [bool] $SkipScripts, [string[]] $AssetRoots = @(), [string[]] $Odfs = @(), [string] $CacheRoot = '', [string] $ModProfile = '', [string] $Converter = '', [string] $MissionProfile = '') {
    $config = Get-PlaytestAssetConfiguration $Game $Mission $AssetProfile $VrvSource $AssetRoots $ModProfile $Converter
    $plan = [pscustomobject]@{
        ModProfile = $config.ModProfile
        MissionProfile = $MissionProfile
        ConverterRoot = $config.ConverterRoot
        LinkedFolders = $config.LinkedFolders
        ExplicitAssetRoots = $config.ExplicitAssetRoots
        ModFolders = $config.ModFolders
        VrvFolders = $config.VrvFolders
        AssetRoots = $config.AssetRoots
        MissingModDependencies = $config.MissingModDependencies
        DependencyCycles = $config.DependencyCycles
        ScriptCheck = 'disabled'
        MissionDll = ''
        ActualBznDll = ''
        ExpectedMissionDll = ''
        DllIdentity = $null
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
        $expectedDll = Get-ExpectedMissionDll $MissionProfile $ModProfile
        $plan.ActualBznDll = if ($dll) { $dll } else { '' }
        $plan.ExpectedMissionDll = $expectedDll
        $plan.ScriptCheck = 'unidentified'
        if ($dll) {
            $roots = @($config.MissionFolder) + @($config.AssetRoots) + @((Join-Path $Game 'Missions')) + @($config.NativeRoots)
            $plan.MissionDll = Find-PlaytestAsset $dll $roots
            if (-not $plan.MissionDll) { throw "Missing mission DLL $dll. Put it beside the map or link its folder in the asset profile." }
            $plan.DllIdentity = Get-DllIdentityInfo $plan.MissionDll $ModProfile $expectedDll $MissionProfile $plan.ActualBznDll
            if ($dll -ieq 'LuaMission.dll') {
                $name = [IO.Path]::GetFileNameWithoutExtension($Mission) + '.lua'
                $plan.LuaScript = Find-PlaytestAsset $name $roots
                if (-not $plan.LuaScript) { throw "Missing Lua mission script $name. Put it beside the map or link its folder in the asset profile." }
            }
            $plan.ScriptCheck = 'resolved'
        } elseif ($expectedDll) {
            $plan.DllIdentity = Get-DllIdentityInfo '' $ModProfile $expectedDll $MissionProfile ''
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