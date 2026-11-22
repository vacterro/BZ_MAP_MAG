[CmdletBinding()]
param(
    [string] $Godot = 'V:/__STORE_V/_SOFT/Godot/4.7.2-stable/Godot_v4.7.2-stable_win64.exe',
    [string] $Game = 'V:/__STORE_V/_SOFT/Steam/steamapps/common/BZ2R',
    [string] $VrvSource = 'V:/___VAC/__K/__CODE/_MISC/_BZDECOMP/vrv',
    [ValidateSet('FAST','INTEGRATION','GUI','PERFORMANCE','GAME','RELEASE')]
    [string] $Level = 'INTEGRATION',
    [switch] $WithGpu,
    [switch] $IncludeGame,
    [switch] $RequireGame,
    [string] $ReportPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')
. (Join-Path $PSScriptRoot 'Playtest-Assets.ps1')

$repo = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$app = Join-Path $repo 'app'
$runRoot = (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ('bzmag-accept-' + [guid]::NewGuid().ToString('N'))) -Force).FullName
$masterLog = Join-Path $runRoot 'godot.log'
$runRecord = New-BzmagRunRecord $repo $runRoot $null

function Get-OptionalFileSha256([string] $Path) {
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return ''
}

function Get-GitStateInfo([string] $RepoRoot) {
    $head = try { (& git -C $RepoRoot rev-parse HEAD 2>$null | Out-String).Trim() } catch { '' }
    $dirtyLines = try { @(& git -C $RepoRoot status --porcelain 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } catch { @() }
    $dirty = ($dirtyLines.Count -gt 0)
    $dirtyFp = ''
    if ($dirty) {
        $diffText = try { (& git -C $RepoRoot diff 2>$null | Out-String) } catch { '' }
        $blob = ($dirtyLines -join "`n") + "`n---DIFF---`n" + $diffText
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $dirtyFp = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($blob))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    return [ordered]@{
        head = $head
        dirty = $dirty
        dirtyCount = $dirtyLines.Count
        dirtyFingerprint = $dirtyFp
    }
}

$gitInfo = Get-GitStateInfo $repo
$srcDigest = Get-BzmagAppSourceDigest $app
$helperProv = Get-BzmagHelperProvenance $repo
$godotVer = if (Test-Path -LiteralPath $Godot -PathType Leaf) {
    try { (& $Godot --version 2>$null | Out-String).Trim() } catch { '' }
} else { '' }
$bzccExe = if ($Game) { Join-Path $Game 'battlezone2.exe' } else { '' }
$bzccVer = if ($bzccExe -and (Test-Path -LiteralPath $bzccExe -PathType Leaf)) {
    (Get-Item -LiteralPath $bzccExe).VersionInfo.FileVersion
} else { '' }

$braveBzn = Join-Path $repo 'map_references/Brave Lil Toaster/braveliltoaster.bzn'
$blankBzn = Join-Path $repo 'map_references/blank_map1/duel_map_27_autosave_01.bzn'
$vsr1197Bzn = Join-Path $repo 'map_references/vsr_1197/vsrterrace2.bzn'
$bolt1200Bzn = Join-Path $repo 'map_references/stbolt_1200_text/STBolt.bzn'
$plgrBzn = if ($Game) { Join-Path $Game 'maps/Missions/Instant/PLGR/plgr.bzn' } else { '' }
$plgrSky = if ($Game) { Join-Path $Game 'maps/Missions/Instant/PLGR/plgr.SKY' } else { '' }

$fixtureHashes = [ordered]@{
    braveBzn = Get-OptionalFileSha256 $braveBzn
    blankBzn = Get-OptionalFileSha256 $blankBzn
    vsr1197Bzn = Get-OptionalFileSha256 $vsr1197Bzn
    bolt1200Bzn = Get-OptionalFileSha256 $bolt1200Bzn
    plgrBzn = Get-OptionalFileSha256 $plgrBzn
    plgrSky = Get-OptionalFileSha256 $plgrSky
}

$stages = [System.Collections.Generic.List[object]]::new()

function Add-StageResult(
    [string] $Name,
    [string] $StageLevel,
    [string] $Status,
    [int] $ExitCode,
    [string] $Command,
    [double] $DurationSec,
    [string] $LogPath,
    [string] $Reason = ''
) {
    $sha = Get-OptionalFileSha256 $LogPath
    $entry = [ordered]@{
        name = $Name
        level = $StageLevel
        status = $Status
        exitCode = $ExitCode
        command = $Command
        durationSec = [Math]::Round($DurationSec, 2)
        logPath = $LogPath
        logSha256 = $sha
        reason = $Reason
    }
    $stages.Add($entry)
    $line = "[{0,-19}] {1,-24} ({2,-11}) exit={3} dur={4:N1}s{5}" -f $Status, $Name, $StageLevel, $ExitCode, $DurationSec, $(if ($Reason) { " — $Reason" } else { '' })
    Write-Output $line
}

function Invoke-GodotScriptStage(
    [string] $Name,
    [string] $StageLevel,
    [string] $ScriptRes,
    [string[]] $ScriptArgs,
    [bool] $UseGpu = $false,
    [int] $TimeoutMs = 300000,
    [bool] $AllowExpectedEngineError = $false
) {
    if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
        Add-StageResult $Name $StageLevel 'BLOCKED' -1 $ScriptRes 0 '' "Godot executable not found: $Godot"
        return
    }
    $stageDir = (New-Item -ItemType Directory -Path (Join-Path $runRoot $Name) -Force).FullName
    $logFile = Join-Path $stageDir 'godot.log'
    $mode = if ($UseGpu) { '--resolution 1280x720' } else { '--headless' }
    $quotedArgs = ($ScriptArgs | ForEach-Object { '"{0}"' -f $_ }) -join ' '
    $argLine = "$mode --path `"$app`" --log-file `"$logFile`" --script $ScriptRes -- $quotedArgs"
    $cmdDisplay = "`"$Godot`" $argLine"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $Godot -ArgumentList $argLine -WindowStyle Hidden -PassThru
    $timedOut = -not $proc.WaitForExit($TimeoutMs)
    if ($timedOut) {
        $proc.Kill()
        $null = $proc.WaitForExit(10000)
    }
    $sw.Stop()
    $lines = if (Test-Path -LiteralPath $logFile -PathType Leaf) { @(Get-Content -LiteralPath $logFile) } else { @() }
    $hasScriptErr = (@($lines -match 'SCRIPT ERROR')).Count -gt 0
    $hasEngineErr = if ($AllowExpectedEngineError) { $false } else { (@($lines -match '^ERROR:')).Count -gt 0 }
    $hasZeroFail = ($lines -contains 'FAILURES: 0')
    $ok = (-not $timedOut) -and ($proc.ExitCode -eq 0) -and (-not $hasScriptErr) -and (-not $hasEngineErr) -and $hasZeroFail
    $reason = if ($timedOut) { "Timed out after $TimeoutMs ms" }
        elseif ($ok) { 'FAILURES: 0' }
        else {
            $failLines = @($lines | Where-Object { $_ -match '^FAIL:|SCRIPT ERROR|^ERROR:|FAILURES:' } | Select-Object -First 4) -join ' | '
            if ($failLines) { $failLines } else { "ExitCode=$($proc.ExitCode)" }
        }
    Add-StageResult $Name $StageLevel $(if ($ok) { 'PASS' } else { 'FAIL' }) $(if ($timedOut) { 124 } else { $proc.ExitCode }) $cmdDisplay $sw.Elapsed.TotalSeconds $logFile $reason
}

function Invoke-PsScriptStage(
    [string] $Name,
    [string] $StageLevel,
    [string] $ScriptPath,
    [string[]] $ArgsList = @()
) {
    $stageDir = (New-Item -ItemType Directory -Path (Join-Path $runRoot $Name) -Force).FullName
    $logFile = Join-Path $stageDir 'stage.log'
    $psExe = (Get-Command powershell.exe).Source
    $allArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ArgsList
    $cmdDisplay = "powershell " + (($allArgs | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join ' ')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = & $psExe @allArgs 2>&1
    $exitCode = $LASTEXITCODE
    $sw.Stop()
    $textLines = @($out | ForEach-Object { $_.ToString() })
    [IO.File]::WriteAllLines($logFile, $textLines, [Text.Encoding]::UTF8)
    $ok = ($exitCode -eq 0)
    $reason = if ($ok) {
        $tail = @($textLines | Where-Object { $_ -match '^PASS:|FAILURES: 0' } | Select-Object -Last 2) -join ' | '
        if ($tail) { $tail } else { 'Exit 0' }
    } else {
        ($textLines | Select-Object -Last 4) -join ' | '
    }
    Add-StageResult $Name $StageLevel $(if ($ok) { 'PASS' } else { 'FAIL' }) $exitCode $cmdDisplay $sw.Elapsed.TotalSeconds $logFile $reason
}

$useGpuEffective = [bool]$WithGpu -or ($Level -in 'GUI','PERFORMANCE','RELEASE')
$runCore = $Level -in 'FAST','INTEGRATION','GUI','RELEASE'
$runIntegration = $Level -in 'INTEGRATION','GUI','RELEASE'
$runPerf = $Level -in 'GUI','PERFORMANCE','RELEASE'
$runBuild = $Level -in 'INTEGRATION','GUI','RELEASE'
$runGame = ($Level -eq 'GAME') -or [bool]$IncludeGame -or [bool]$RequireGame

Write-Output "BZ_MAP_MAG Canonical Acceptance Runner | Level=$Level | GPU=$useGpuEffective | Head=$($gitInfo.head.Substring(0, [Math]::Min(7, $gitInfo.head.Length))) | Dirty=$($gitInfo.dirty) | Run=$runRoot"

# 1. FAST: BZN Layouts, Autosave Store, Playtest Asset Safety, Run Hygiene
if ($runCore) {
    Invoke-PsScriptStage 'bzn-layouts' 'FAST' (Join-Path $PSScriptRoot 'Test-BznLayouts.ps1') @('-Godot', $Godot)
    Invoke-PsScriptStage 'autosave-store' 'FAST' (Join-Path $PSScriptRoot 'Test-AutosaveStore.ps1') @('-Godot', $Godot)
    if (-not (Test-Path -LiteralPath $Game -PathType Container) -or -not (Test-Path -LiteralPath $VrvSource -PathType Container)) {
        Add-StageResult 'playtest-assets' 'FAST' 'BLOCKED' -1 'tools/Test-PlaytestAssets.ps1' 0 '' 'Missing BZCC game dir or VRV checkout required by Test-PlaytestAssets.ps1.'
    } else {
        Invoke-PsScriptStage 'playtest-assets' 'FAST' (Join-Path $PSScriptRoot 'Test-PlaytestAssets.ps1') @('-Game', $Game, '-Godot', $Godot, '-VrvSource', $VrvSource)
    }
    Invoke-PsScriptStage 'run-hygiene' 'FAST' (Join-Path $PSScriptRoot 'Test-RunHygiene.ps1') @()
} else {
    foreach ($n in 'bzn-layouts','autosave-store','playtest-assets','run-hygiene') {
        Add-StageResult $n 'FAST' 'SKIPPED_WITH_REASON' 0 '' 0 '' "Not in selected level '$Level'."
    }
}

# 2. INTEGRATION / GUI: Core Terrain Workflow, Compatibility Truth, Object Authoring, Environment & Mission
if ($runIntegration) {
    if (-not (Test-Path -LiteralPath $braveBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $blankBzn -PathType Leaf)) {
        Add-StageResult 'terrain-workflow' $(if ($useGpuEffective) { 'GUI' } else { 'INTEGRATION' }) 'BLOCKED' -1 'res://tests/terrain_workflow.gd' 0 '' 'Missing Brave or Blank map_references fixture.'
    } else {
        $twScratch = (New-Item -ItemType Directory -Path (Join-Path $runRoot 'terrain-workflow-scratch') -Force).FullName
        Invoke-GodotScriptStage 'terrain-workflow' $(if ($useGpuEffective) { 'GUI' } else { 'INTEGRATION' }) 'res://tests/terrain_workflow.gd' @($braveBzn, $blankBzn, $twScratch) $useGpuEffective 600000
    }

    if (-not (Test-Path -LiteralPath $Game -PathType Container) -or -not (Test-Path -LiteralPath $braveBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $blankBzn -PathType Leaf)) {
        Add-StageResult 'compatibility-truth' 'INTEGRATION' 'BLOCKED' -1 'res://tests/compatibility_truth.gd' 0 '' 'Missing real BZCC game dir or map_references fixtures.'
    } else {
        $ctScratch = (New-Item -ItemType Directory -Path (Join-Path $runRoot 'compatibility-truth-scratch') -Force).FullName
        $ctArgs = @($braveBzn, $blankBzn, $ctScratch, $Game)
        if ($VrvSource -and (Test-Path -LiteralPath $VrvSource -PathType Container)) { $ctArgs += $VrvSource }
        Invoke-GodotScriptStage 'compatibility-truth' 'INTEGRATION' 'res://tests/compatibility_truth.gd' $ctArgs $false 240000
    }

    if (-not (Test-Path -LiteralPath $plgrBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $Game -PathType Container)) {
        Add-StageResult 'object-authoring' 'INTEGRATION' 'BLOCKED' -1 'res://tests/object_authoring.gd' 0 '' "Missing Stock plgr.bzn or game dir ($plgrBzn)."
    } else {
        $oaScratch = (New-Item -ItemType Directory -Path (Join-Path $runRoot 'object-authoring-scratch') -Force).FullName
        $oaArgs = @($plgrBzn, $Game, $oaScratch)
        if ($VrvSource -and (Test-Path -LiteralPath $VrvSource -PathType Container)) { $oaArgs += $VrvSource }
        Invoke-GodotScriptStage 'object-authoring' 'INTEGRATION' 'res://tests/object_authoring.gd' $oaArgs $false 240000
    }

    if (-not (Test-Path -LiteralPath $plgrBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $braveBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $Game -PathType Container)) {
        Add-StageResult 'env-and-mission' 'INTEGRATION' 'BLOCKED' -1 'res://tests/env_and_mission.gd' 0 '' "Missing Stock plgr.bzn, Brave fixture or game dir."
    } else {
        $emScratch = (New-Item -ItemType Directory -Path (Join-Path $runRoot 'env-and-mission-scratch') -Force).FullName
        $emArgs = @($plgrBzn, $braveBzn, $Game, $emScratch)
        if ($VrvSource -and (Test-Path -LiteralPath $VrvSource -PathType Container)) { $emArgs += $VrvSource }
        Invoke-GodotScriptStage 'env-and-mission' 'INTEGRATION' 'res://tests/env_and_mission.gd' $emArgs $false 240000
    }
} else {
    foreach ($n in 'terrain-workflow','compatibility-truth','object-authoring','env-and-mission') {
        Add-StageResult $n 'INTEGRATION' 'SKIPPED_WITH_REASON' 0 '' 0 '' "Not in selected level '$Level'."
    }
}

# 3. PERFORMANCE + MULTI-RES UI BATTERY
if ($runPerf) {
    if (-not (Test-Path -LiteralPath $braveBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $plgrBzn -PathType Leaf) -or -not (Test-Path -LiteralPath $Game -PathType Container)) {
        Add-StageResult 'perf-and-ui-battery' 'PERFORMANCE' 'BLOCKED' -1 'res://tests/perf_and_ui_battery.gd' 0 '' 'Missing Brave, plgr.bzn or game dir.'
    } else {
        $puScratch = (New-Item -ItemType Directory -Path (Join-Path $runRoot 'perf-ui-scratch') -Force).FullName
        $puArgs = @($braveBzn, $plgrBzn, $Game, $puScratch)
        if ($VrvSource -and (Test-Path -LiteralPath $VrvSource -PathType Container)) { $puArgs += $VrvSource }
        Invoke-GodotScriptStage 'perf-and-ui-battery' 'PERFORMANCE' 'res://tests/perf_and_ui_battery.gd' $puArgs $useGpuEffective 360000
    }
} else {
    Add-StageResult 'perf-and-ui-battery' 'PERFORMANCE' 'SKIPPED_WITH_REASON' 0 '' 0 '' "Omitted for level '$Level'; run with -Level GUI, PERFORMANCE or RELEASE."
}

# 4. BUILD INTEGRITY
if ($runBuild) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $bLog = Join-Path $runRoot 'build-integrity.log'
    $bNotes = [System.Collections.Generic.List[string]]::new()
    $bOk = $true
    $bExit = 0
    try {
        $rootExe = Join-Path $repo 'BZ_MAP_MAG.exe'
        $rootPck = Join-Path $repo 'BZ_MAP_MAG.pck'
        $rootMan = Join-Path $repo 'BZ_MAP_MAG.manifest.json'
        $rootRel = Join-Path $repo 'BZ_MAP_MAG.release.json'
        foreach ($req in $rootExe,$rootPck,$rootMan,$rootRel) {
            if (-not (Test-Path -LiteralPath $req -PathType Leaf)) {
                throw "Missing build artifact: $(Split-Path -Leaf $req) (rebuild with tools/Build-Desktop.ps1 -ToRoot)"
            }
        }
        $man = Get-Content -LiteralPath $rootMan -Raw -Encoding UTF8 | ConvertFrom-Json
        $rel = Get-Content -LiteralPath $rootRel -Raw -Encoding UTF8 | ConvertFrom-Json
        $livePck = Get-OptionalFileSha256 $rootPck
        $liveExe = Get-OptionalFileSha256 $rootExe
        if ($man.schema -ne 'bzmag.build-manifest/3') { throw "Unexpected manifest schema: $($man.schema)" }
        if ($man.sourceDigest -ne $srcDigest) { throw "Stale BZ_MAP_MAG.pck: manifest sourceDigest $($man.sourceDigest) != live $srcDigest" }
        if ($man.helpersDigest -ne $helperProv.Digest) { throw "Stale helpersDigest: manifest $($man.helpersDigest) != live $($helperProv.Digest)" }
        if ($man.pckSha256 -ne $livePck) { throw "PCK SHA-256 mismatch" }
        if ($man.exeSha256 -ne $liveExe) { throw "EXE SHA-256 mismatch" }
        if ($rel.buildRevision -ne $man.buildRevision -or $rel.pckSha256 -ne $livePck) { throw "Release pointer mismatch vs manifest" }
        $bNotes.Add("Manifest v3 & release pointer verified: buildRevision=$($man.buildRevision)")

        $smokeLog = Join-Path $runRoot 'build-smoke.log'
        $smoke = Start-Process -FilePath $rootExe -ArgumentList "--headless --log-file `"$smokeLog`" --quit" -WorkingDirectory $repo -WindowStyle Hidden -PassThru
        if (-not $smoke.WaitForExit(30000) -or $smoke.ExitCode -ne 0) {
            throw "BZ_MAP_MAG.exe --headless --quit failed (exit $($smoke.ExitCode))"
        }
        $bNotes.Add("Packaged BZ_MAP_MAG.exe --headless --quit exited 0")

        $validateMission = ''
        $emLogForBuild = Join-Path $runRoot 'env-and-mission\godot.log'
        if (Test-Path -LiteralPath $emLogForBuild -PathType Leaf) {
            $mExp = Select-String -Path $emLogForBuild -Pattern '^EXPORTED_W567_PLAYTEST_BZN=(.+)$' | Select-Object -First 1
            if ($mExp) {
                $candExp = $mExp.Matches[0].Groups[1].Value.Trim()
                if (Test-Path -LiteralPath $candExp -PathType Leaf) { $validateMission = $candExp }
            }
        }
        if (-not $validateMission -and (Test-Path -LiteralPath $plgrBzn -PathType Leaf)) {
            $stageDir = Join-Path $runRoot 'build-validate-stock'
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
            foreach ($item in Get-ChildItem -LiteralPath (Split-Path -Parent $plgrBzn) -Filter 'plgr.*' -File) {
                Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $stageDir $item.Name) -Force
            }
            $stageInf = Join-Path $stageDir 'plgr.inf'
            if (-not (Test-Path -LiteralPath $stageInf -PathType Leaf)) {
                [IO.File]::WriteAllText($stageInf, "[DESCRIPTION]`r`nmissionName = `"plgr`"`r`n", [Text.Encoding]::ASCII)
            }
            $validateMission = Join-Path $stageDir 'plgr.bzn'
        }
        if ($validateMission) {
            $valOut = & (Join-Path $PSScriptRoot 'Start-Playtest.ps1') -Game $Game -ModProfile stock -Mission $validateMission -ValidateOnly
            if ($valOut.LaunchRoute -ne 'native' -or $valOut.BznVersion -ne 1192) {
                throw "Packaged validator returned unexpected route=$($valOut.LaunchRoute) ver=$($valOut.BznVersion)"
            }
            $bNotes.Add("Packaged Start-Playtest.ps1 -ValidateOnly (no -Godot) admitted Stock 1192 native ($validateMission)")
        }
    } catch {
        $bOk = $false
        $bExit = 1
        $bNotes.Add("FAIL: $($_.Exception.Message)")
    }
    $sw.Stop()
    [IO.File]::WriteAllLines($bLog, $bNotes, [Text.Encoding]::UTF8)
    Add-StageResult 'build-integrity' 'INTEGRATION' $(if ($bOk) { 'PASS' } else { 'FAIL' }) $bExit 'Build manifest v3 + EXE smoke + packaged -ValidateOnly' $sw.Elapsed.TotalSeconds $bLog ($bNotes[-1])
} else {
    Add-StageResult 'build-integrity' 'INTEGRATION' 'SKIPPED_WITH_REASON' 0 '' 0 '' "Not in selected level '$Level'."
}

# 5. OPTIONAL REAL BZCC GAME ACCEPTANCE
if ($runGame) {
    $gLog = Join-Path $runRoot 'game-playtest.log'
    if (-not (Test-Path -LiteralPath $bzccExe -PathType Leaf) -or $bzccVer -ne '2.0.185') {
        Add-StageResult 'game-playtest' 'GAME' 'BLOCKED' -1 'Start-Playtest.ps1' 0 '' "BZCC 2.0.185 executable missing ($bzccExe, ver=$bzccVer)."
    } elseif (-not (Get-Process steam -ErrorAction SilentlyContinue)) {
        Add-StageResult 'game-playtest' 'GAME' 'BLOCKED' -1 'Start-Playtest.ps1' 0 '' 'Steam is not running.'
    } elseif (Get-Process battlezone2 -ErrorAction SilentlyContinue) {
        $extBz = Get-Process battlezone2 -ErrorAction SilentlyContinue | Select-Object -First 1
        Add-StageResult 'game-playtest' 'GAME' 'BLOCKED' -1 'Start-Playtest.ps1' 0 '' "External battlezone2.exe session already running (PID $($extBz.Id)); refusing to disturb user session."
    } else {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $emLog = Join-Path $runRoot 'env-and-mission\godot.log'
        $exportedBzn = ''
        if (Test-Path -LiteralPath $emLog -PathType Leaf) {
            $m = Select-String -Path $emLog -Pattern '^EXPORTED_W567_PLAYTEST_BZN=(.+)$' | Select-Object -First 1
            if ($m) { $exportedBzn = $m.Matches[0].Groups[1].Value.Trim() }
        }
        if (-not $exportedBzn -or -not (Test-Path -LiteralPath $exportedBzn -PathType Leaf)) {
            $exportedBzn = $plgrBzn
        }
        $docsDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games/Battlezone Combat Commander'
        $startUtc = [DateTime]::UtcNow.AddSeconds(-2)
        $beforeNames = @{}
        Get-ChildItem -LiteralPath $docsDir -Filter 'Battlezone*.log' -ErrorAction SilentlyContinue | ForEach-Object { $beforeNames[$_.Name] = $true }
        try {
            $launch = & (Join-Path $PSScriptRoot 'Start-Playtest.ps1') -Game $Game -Godot $Godot -ModProfile stock -MissionProfile strategy -Mission $exportedBzn
            $bzPid = [int]$launch.ProcessId
            $runToken = Split-Path -Leaf ([string]$launch.Run)
            $reached = $false
            $deadline = [DateTime]::UtcNow.AddSeconds(75)
            while ([DateTime]::UtcNow -lt $deadline) {
                $p = Get-Process -Id $bzPid -ErrorAction SilentlyContinue
                $cand = Get-ChildItem -LiteralPath $docsDir -Filter 'Battlezone*.log' -ErrorAction SilentlyContinue |
                    Where-Object { -not $beforeNames.ContainsKey($_.Name) -or $_.LastWriteTimeUtc -ge $startUtc } |
                    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                if ($cand) {
                    try {
                        $fs = [IO.File]::Open($cand.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                        $sr = New-Object IO.StreamReader($fs)
                        $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
                        if ($txt -match '\[Main\] Entering run code \[MISSION\]' -and $txt -match '\[Mission\] Entering run code \[RUN\]') {
                            $reached = $true; break
                        }
                    } catch {}
                }
                if (-not $p -or $p.HasExited) { break }
                Start-Sleep -Milliseconds 500
            }
            if ($reached) {
                Start-Sleep -Seconds 3
                if (-not ('BzAcceptWin32' -as [type])) {
                    Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class BzAcceptWin32 {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public static IntPtr FindMainWindow(uint targetPid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == targetPid) {
                var t = new StringBuilder(256); GetWindowText(h, t, 256);
                if (t.ToString().Contains("BZCC") || t.ToString().Contains("Battlezone")) { found = h; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
                }
                $hwnd = [BzAcceptWin32]::FindMainWindow([uint32]$bzPid)
                if ($hwnd -ne [IntPtr]::Zero) {
                    [void][BzAcceptWin32]::PostMessage($hwnd, 0x0112, [IntPtr]0xF060, [IntPtr]::Zero)
                    Start-Sleep -Milliseconds 400
                    $p = Get-Process -Id $bzPid -ErrorAction SilentlyContinue
                    if ($p -and -not $p.HasExited) {
                        [void][BzAcceptWin32]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
                    }
                } else {
                    $p = Get-Process -Id $bzPid -ErrorAction SilentlyContinue
                    if ($p -and -not $p.HasExited) { $null = $p.CloseMainWindow() }
                }
                $exWait = [DateTime]::UtcNow.AddSeconds(20)
                while ([DateTime]::UtcNow -lt $exWait) {
                    $p = Get-Process -Id $bzPid -ErrorAction SilentlyContinue
                    if (-not $p -or $p.HasExited) { break }
                    Start-Sleep -Milliseconds 300
                }
            }
            $p = Get-Process -Id $bzPid -ErrorAction SilentlyContinue
            if ($p -and -not $p.HasExited) {
                & (Join-Path $PSScriptRoot 'Stop-OwnedProcesses.ps1') -Apply -RunToken $runToken | Out-Null
            }
            Start-Sleep -Seconds 1
            $finalLog = Get-ChildItem -LiteralPath $docsDir -Filter 'Battlezone*.log' -ErrorAction SilentlyContinue |
                Where-Object { -not $beforeNames.ContainsKey($_.Name) -or $_.LastWriteTimeUtc -ge $startUtc } |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            $sw.Stop()
            $logRaw = if ($finalLog) { Get-Content -LiteralPath $finalLog.FullName -Raw } else { '' }
            $gOk = $reached -and $finalLog -and ($logRaw -notmatch 'SAVEGAME CORRUPT') -and ($logRaw -match 'System shutdown normally') -and ($finalLog.Name -notlike 'Battlezone-Crashed*')
            $gSha = if ($finalLog) { Get-OptionalFileSha256 $finalLog.FullName } else { '' }
            $summary = "mission=$exportedBzn log=$($finalLog.Name) sha256=$gSha reachedRun=$reached normalExit=$($logRaw -match 'System shutdown normally')"
            [IO.File]::WriteAllText($gLog, $summary, [Text.Encoding]::UTF8)
            Add-StageResult 'game-playtest' 'GAME' $(if ($gOk) { 'PASS' } else { 'FAIL' }) $(if ($gOk) { 0 } else { 1 }) "Start-Playtest.ps1 -ModProfile stock -Mission `"$exportedBzn`"" $sw.Elapsed.TotalSeconds $gLog $summary
        } catch {
            $sw.Stop()
            [IO.File]::WriteAllText($gLog, $_.Exception.Message, [Text.Encoding]::UTF8)
            Add-StageResult 'game-playtest' 'GAME' 'FAIL' 1 "Start-Playtest.ps1" $sw.Elapsed.TotalSeconds $gLog $_.Exception.Message
        }
    }
} else {
    Add-StageResult 'game-playtest' 'GAME' 'SKIPPED_WITH_REASON' 0 '' 0 '' "Real BZCC Playtest omitted; pass -IncludeGame or -Level GAME."
}

$counts = [ordered]@{
    pass = (@($stages | Where-Object { $_.status -eq 'PASS' })).Count
    fail = (@($stages | Where-Object { $_.status -eq 'FAIL' })).Count
    blocked = (@($stages | Where-Object { $_.status -eq 'BLOCKED' })).Count
    skipped = (@($stages | Where-Object { $_.status -eq 'SKIPPED_WITH_REASON' })).Count
}

$releaseReady = (
    $Level -eq 'RELEASE' -and
    $counts.fail -eq 0 -and
    $counts.blocked -eq 0 -and
    (-not $gitInfo.dirty) -and
    $useGpuEffective -and
    ((-not $RequireGame) -or $counts.skipped -eq 0)
)
$verdict = if ($counts.fail -gt 0 -or $counts.blocked -gt 0) {
    'NOT_READY'
} elseif ($releaseReady) {
    'READY_FOR_RELEASE'
} elseif ($counts.skipped -gt 0 -or $gitInfo.dirty) {
    'PASS_PARTIAL'
} else {
    'PASS'
}

$report = [ordered]@{
    schema = 'bzmag.acceptance-report/1'
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    level = $Level
    gpuEnabled = $useGpuEffective
    verdict = $verdict
    sourceRevision = $gitInfo.head
    gitDirty = $gitInfo.dirty
    gitDirtyCount = $gitInfo.dirtyCount
    dirtyFingerprint = $gitInfo.dirtyFingerprint
    sourceDigest = $srcDigest
    helpersDigest = $helperProv.Digest
    toolVersions = [ordered]@{
        godot = $godotVer
        powershell = $PSVersionTable.PSVersion.ToString()
        bzcc = $bzccVer
    }
    fixtureHashes = $fixtureHashes
    counts = $counts
    runRoot = $runRoot
    stages = $stages
}

$finalReportPath = if ($ReportPath) { $ReportPath } else { Join-Path $runRoot 'acceptance-report.json' }
$reportJson = $report | ConvertTo-Json -Depth 6
[IO.File]::WriteAllText($finalReportPath, $reportJson, [Text.Encoding]::UTF8)

$logSummary = @(
    "BZ_MAP_MAG Acceptance Report ($verdict)"
    "Level=$Level GPU=$useGpuEffective Head=$($gitInfo.head) Dirty=$($gitInfo.dirty) SourceDigest=$srcDigest"
    "Counts: PASS=$($counts.pass) FAIL=$($counts.fail) BLOCKED=$($counts.blocked) SKIPPED=$($counts.skipped)"
    "Report: $finalReportPath"
) + @($stages | ForEach-Object { "$($_.status) $($_.name) exit=$($_.exitCode) log=$($_.logPath) sha=$($_.logSha256) $($_.reason)" }) + @(
    "FAILURES: $($counts.fail + $counts.blocked)"
)
[IO.File]::WriteAllLines($masterLog, $logSummary, [Text.Encoding]::UTF8)
Complete-BzmagRunRecord $runRecord $masterLog ($counts.fail -eq 0 -and $counts.blocked -eq 0)

Write-Output "VERDICT=$verdict PASS=$($counts.pass) FAIL=$($counts.fail) BLOCKED=$($counts.blocked) SKIPPED=$($counts.skipped)"
Write-Output "REPORT=$finalReportPath"
Write-Output "MASTER_LOG=$masterLog SHA256=$($runRecord.log_sha256)"

if ($counts.fail -gt 0 -or $counts.blocked -gt 0) {
    exit 1
}
if ($Level -eq 'RELEASE' -and -not $releaseReady) {
    exit 2
}
exit 0
