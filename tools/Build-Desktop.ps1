[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot,
    [string] $WindowsReleaseTemplate,
    [switch] $ToRoot,
    [switch] $RequireClean,
    [switch] $SimulatePublishFailure
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Playtest-Assets.ps1')
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
if (-not $WindowsReleaseTemplate) {
    $candidate = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable\windows_release_x86_64.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $WindowsReleaseTemplate = $candidate
    } else {
        throw 'Pass -WindowsReleaseTemplate with the Godot windows_release_x86_64.exe template.'
    }
}
$stage = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/desktop-' + [guid]::NewGuid().ToString('N'))) -Force).FullName
$pack = Join-Path $stage 'BZ_MAP_MAG.pck'
$stageExe = Join-Path $stage 'BZ_MAP_MAG.exe'
$manifestPath = Join-Path $stage 'BZ_MAP_MAG.manifest.json'
$log = Join-Path $stage 'export.log'
# Re-import project resources (including embedded Verdana_m1 bitmap strikes) before pack export.
$importCmd = "--headless --path `"$app`" --import"
$null = Start-Process -FilePath $Godot -ArgumentList $importCmd -WindowStyle Hidden -PassThru -Wait
$command = "--headless --path `"$app`" --log-file `"$log`" --export-pack `"Windows Desktop`" `"$pack`""
$process = Start-Process -FilePath $Godot -ArgumentList $command -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $pack -PathType Leaf)) {
    throw "Godot could not export the pack. See $log"
}
Copy-Item -LiteralPath $WindowsReleaseTemplate -Destination $stageExe -Force
$gitHead = try { (& git -C $repo rev-parse HEAD 2>$null | Out-String).Trim() } catch { '' }
$gitShort = if ($gitHead.Length -ge 7) { $gitHead.Substring(0, 7) } else { 'nogit' }
$dirtyRaw = try { @(& git -C $repo status --porcelain 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } catch { @() }
$gitDirty = ($dirtyRaw.Count -gt 0)
if ($RequireClean -and $gitDirty) {
    throw "Refusing clean release build: working tree has $($dirtyRaw.Count) uncommitted change(s). Commit or stash before building with -RequireClean."
}
$dirtyFingerprint = ''
if ($gitDirty) {
    $diffText = try { (& git -C $repo diff 2>$null | Out-String) } catch { '' }
    $diffBlob = ($dirtyRaw -join "`n") + "`n---DIFF---`n" + $diffText
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $dirtyFingerprint = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($diffBlob))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
$godotVer = try { (& $Godot --version 2>$null | Out-String).Trim() } catch { '4.7.2.stable' }
$srcDigest = Get-BzmagAppSourceDigest $app
$impDigest = Get-BzmagImportDigest $app
$helperProv = Get-BzmagHelperProvenance $repo
$pckHash = (Get-FileHash -LiteralPath $pack -Algorithm SHA256).Hash.ToLowerInvariant()
$exeHash = (Get-FileHash -LiteralPath $stageExe -Algorithm SHA256).Hash.ToLowerInvariant()
$stateTag = if ($gitDirty) { 'dirty-' + $dirtyFingerprint.Substring(0, 8) } else { 'clean' }
$buildRev = "$gitShort-$($srcDigest.Substring(0, 12))-$stateTag"
$builtAtUtc = [DateTime]::UtcNow.ToString('o')
$manifest = [ordered]@{
    schema = 'bzmag.build-manifest/3'
    buildRevision = $buildRev
    sourceDigest = $srcDigest
    importDigest = $impDigest
    helpersDigest = $helperProv.Digest
    helpers = $helperProv.Helpers
    schemas = [ordered]@{
        manifest = 'bzmag.build-manifest/3'
        compatibility = 'bzmag.compatibility-result/1'
        project = 1
    }
    pckSha256 = $pckHash
    exeSha256 = $exeHash
    gitHead = $gitHead
    gitDirty = $gitDirty
    gitDirtyCount = $dirtyRaw.Count
    dirtyFingerprint = $dirtyFingerprint
    godotVersion = $godotVer
    buildMode = 'release'
    buildTarget = if ($ToRoot) { 'root-executable' } else { 'portable-desktop' }
    builtAtUtc = $builtAtUtc
}
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)

# Validate staged binary + pack before publishing
$smokeLog = Join-Path $stage 'smoke.log'
$smokeProc = Start-Process -FilePath $stageExe -ArgumentList "--headless --log-file `"$smokeLog`" --quit" -WorkingDirectory $stage -WindowStyle Hidden -PassThru -Wait
if ($smokeProc.ExitCode -ne 0) {
    throw "Staged desktop build failed headless startup verification (exit $($smokeProc.ExitCode)). See $smokeLog"
}

if ($ToRoot) {
    # Stage an immutable versioned release directory before publishing root pointers
    $releasesRoot = (New-Item -ItemType Directory -Path (Join-Path $repo 'build/releases') -Force).FullName
    $releaseDir = Join-Path $releasesRoot $buildRev
    if (-not $SimulatePublishFailure -and -not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
        $relTemp = Join-Path $releasesRoot ('.stage-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $relTemp -Force
        try {
            Copy-Item -LiteralPath $pack -Destination (Join-Path $relTemp 'BZ_MAP_MAG.pck') -Force
            Copy-Item -LiteralPath $stageExe -Destination (Join-Path $relTemp 'BZ_MAP_MAG.exe') -Force
            Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $relTemp 'BZ_MAP_MAG.manifest.json') -Force
            $relTools = (New-Item -ItemType Directory -Path (Join-Path $relTemp 'tools') -Force).FullName
            foreach ($name in 'Start-Playtest.ps1','Playtest-Assets.ps1','Run-Ownership.ps1','Find-Bzcc.ps1','New-FlatTerrainSnapshot.ps1') {
                Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $relTools -Force
            }
            $meshPreview = Join-Path $repo 'build/object-preview/mesh-preview.exe'
            if (Test-Path -LiteralPath $meshPreview -PathType Leaf) {
                Copy-Item -LiteralPath $meshPreview -Destination $relTools -Force
            }
            Move-Item -LiteralPath $relTemp -Destination $releaseDir
        } catch {
            Remove-Item -LiteralPath $relTemp -Recurse -Force -ErrorAction SilentlyContinue
            throw
        }
    }
    $releasePointerPath = Join-Path $stage 'BZ_MAP_MAG.release.json'
    $releasePointer = [ordered]@{
        schema = 'bzmag.release-pointer/1'
        buildRevision = $buildRev
        releaseDir = "build/releases/$buildRev"
        pckSha256 = $pckHash
        exeSha256 = $exeHash
        sourceDigest = $srcDigest
        helpersDigest = $helperProv.Digest
        publishedAtUtc = $builtAtUtc
    }
    [IO.File]::WriteAllText($releasePointerPath, ($releasePointer | ConvertTo-Json -Depth 4), [Text.Encoding]::UTF8)

    $items = @(
        @{ Name = 'BZ_MAP_MAG.pck'; Staged = $pack; Hash = $pckHash },
        @{ Name = 'BZ_MAP_MAG.exe'; Staged = $stageExe; Hash = $exeHash },
        @{ Name = 'BZ_MAP_MAG.manifest.json'; Staged = $manifestPath; Hash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() },
        @{ Name = 'BZ_MAP_MAG.release.json'; Staged = $releasePointerPath; Hash = (Get-FileHash -LiteralPath $releasePointerPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    )
    $hadExisting = @{}
    try {
        foreach ($it in $items) {
            $newPath = Join-Path $repo ($it.Name + '.new')
            Copy-Item -LiteralPath $it.Staged -Destination $newPath -Force
            if ((Get-FileHash -LiteralPath $newPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $it.Hash) {
                throw "Staged root copy hash mismatch for $($it.Name)."
            }
        }
        foreach ($it in $items) {
            $livePath = Join-Path $repo $it.Name
            $bakPath = Join-Path $repo ($it.Name + '.bak')
            if (Test-Path -LiteralPath $bakPath) { Remove-Item -LiteralPath $bakPath -Force }
            if (Test-Path -LiteralPath $livePath -PathType Leaf) {
                Copy-Item -LiteralPath $livePath -Destination $bakPath -Force
                $hadExisting[$it.Name] = $true
            } else {
                $hadExisting[$it.Name] = $false
            }
        }
        $stepIdx = 0
        foreach ($it in $items) {
            $stepIdx++
            if ($SimulatePublishFailure -and $stepIdx -eq 2) {
                throw 'Simulated root deployment interruption after first file swap.'
            }
            $livePath = Join-Path $repo $it.Name
            $newPath = Join-Path $repo ($it.Name + '.new')
            if (Test-Path -LiteralPath $livePath) {
                [IO.File]::Replace($newPath, $livePath, [NullString]::Value)
            } else {
                [IO.File]::Move($newPath, $livePath)
            }
        }
        foreach ($it in $items) {
            $livePath = Join-Path $repo $it.Name
            if (-not (Test-Path -LiteralPath $livePath -PathType Leaf) -or
                (Get-FileHash -LiteralPath $livePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $it.Hash) {
                throw "Post-publish verification failed for $($it.Name)."
            }
        }
        foreach ($it in $items) {
            $bakPath = Join-Path $repo ($it.Name + '.bak')
            if (Test-Path -LiteralPath $bakPath) { Remove-Item -LiteralPath $bakPath -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        $publishErr = $_
        foreach ($it in $items) {
            $livePath = Join-Path $repo $it.Name
            $newPath = Join-Path $repo ($it.Name + '.new')
            $bakPath = Join-Path $repo ($it.Name + '.bak')
            if (Test-Path -LiteralPath $newPath) { Remove-Item -LiteralPath $newPath -Force -ErrorAction SilentlyContinue }
            if ($hadExisting[$it.Name] -and (Test-Path -LiteralPath $bakPath -PathType Leaf)) {
                Move-Item -LiteralPath $bakPath -Destination $livePath -Force -ErrorAction SilentlyContinue
            }
        }
        throw $publishErr
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-Item -LiteralPath (Join-Path $repo 'BZ_MAP_MAG.exe'), (Join-Path $repo 'BZ_MAP_MAG.pck'), (Join-Path $repo 'BZ_MAP_MAG.manifest.json'), (Join-Path $repo 'BZ_MAP_MAG.release.json') | Select-Object Name,Length
    $repo
    return
}
$target = $stage
$tools = (New-Item -ItemType Directory -Path (Join-Path $target 'tools')).FullName
foreach ($name in 'Start-Playtest.ps1','Playtest-Assets.ps1','Run-Ownership.ps1','Find-Bzcc.ps1','New-FlatTerrainSnapshot.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $tools
}
$meshPreview = Join-Path $repo 'build/object-preview/mesh-preview.exe'
if (Test-Path -LiteralPath $meshPreview -PathType Leaf) {
    Copy-Item -LiteralPath $meshPreview -Destination $tools
}
Get-ChildItem -LiteralPath $target -File | Select-Object Name,Length
$target
