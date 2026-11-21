[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Run-Ownership.ps1')

function New-FixtureDirectory([string] $Path) {
    return [IO.Directory]::CreateDirectory($Path).FullName
}

function Assert-Hygiene([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$fixture = New-FixtureDirectory (Join-Path $repo ('build/test-' + [guid]::NewGuid().ToString('N')))
$workspace = New-FixtureDirectory (Join-Path $fixture 'workspace')
$bin = New-FixtureDirectory (Join-Path $workspace 'tools')
$docs = New-FixtureDirectory (Join-Path $workspace 'docs')
$evidence = Join-Path $docs 'EVIDENCE.md'
foreach ($script in 'Clean-Build.ps1','Clean-TempEvidence.ps1','Stop-OwnedProcesses.ps1','Run-Ownership.ps1') {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $script) -Destination $bin
}
$cleanBuild = Join-Path $bin 'Clean-Build.ps1'
$cleanTemp = Join-Path $bin 'Clean-TempEvidence.ps1'
$stop = Join-Path $bin 'Stop-OwnedProcesses.ps1'
$build = New-FixtureDirectory (Join-Path $workspace 'build')
$preview = New-FixtureDirectory (Join-Path $build 'object-preview')
$oracle = Join-Path $build 'terrain_oracle.exe'
[IO.File]::WriteAllText($oracle, 'protected')
foreach ($group in 'BZMAG','bzn-185','sdk') {
    for ($index = 0; $index -lt 3; $index++) {
        $path = New-FixtureDirectory (Join-Path $build ($group + '-' + [guid]::NewGuid().ToString('N')))
        [IO.Directory]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddHours(-$index))
    }
}
foreach ($keep in 0, 1, 2) {
    $expired = @(& $cleanBuild -Keep $keep)
    Assert-Hygiene ($expired.Count -eq 3 * (3 - $keep)) "Wrong build retention for Keep $keep."
    Assert-Hygiene (@($expired | Where-Object Present).Count -eq $expired.Count) 'Build dry-run deleted a fixture.'
}
$null = & $cleanBuild -Keep 1 -Apply
Assert-Hygiene (@(& $cleanBuild -Keep 0).Count -eq 3) 'Build Keep 1 did not protect one member per group.'
$null = & $cleanBuild -Keep 0 -Apply
Assert-Hygiene (@(& $cleanBuild).Count -eq 0) 'Build cleanup is not idempotent.'
Assert-Hygiene ((Test-Path -LiteralPath $preview) -and (Test-Path -LiteralPath $oracle)) 'Build cleanup touched protected tools.'

foreach ($keep in 0, 1, 2) {
    $temp = New-FixtureDirectory (Join-Path $fixture "temp-$keep")
    $foreign = New-FixtureDirectory (Join-Path $temp 'native-route-probe')
    $entries = for ($index = 0; $index -lt 7; $index++) {
        $path = New-FixtureDirectory (Join-Path $temp ('bzmag-terrain-' + [guid]::NewGuid().ToString('N')))
        $record = New-BzmagRunRecord $workspace $path $null
        $log = Join-Path $path 'godot.log'
        [IO.File]::WriteAllText($log, "evidence $index")
        Complete-BzmagRunRecord $record $log ($index -notin 1, 4)
        [IO.Directory]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddHours(-$index - 2))
        if ($index -lt 6) { "$($record.token) $($record.log_sha256)" | Add-Content -LiteralPath $evidence }
        [pscustomobject]@{ Path = $path; Token = $record.token; Hash = $record.log_sha256 }
    }
    $dry = @(& $cleanTemp -TempRoot $temp -Keep $keep 6>&1 | ForEach-Object ToString)
    Assert-Hygiene (@($dry -match '^REMOVE ').Count -eq (4 - $keep)) "Wrong temp retention for Keep $keep."
    Assert-Hygiene (@(Get-ChildItem -LiteralPath $temp -Directory).Count -eq 8) 'Temp dry-run deleted a fixture.'
    $null = & $cleanTemp -TempRoot $temp -Keep $keep -Apply 6>&1
    Assert-Hygiene (@(Get-ChildItem -LiteralPath $temp -Directory).Count -eq (4 + $keep)) "Wrong temp removal for Keep $keep."
    foreach ($path in $foreign,$entries[0].Path,$entries[1].Path,$entries[6].Path) {
        Assert-Hygiene (Test-Path -LiteralPath $path -PathType Container) 'Cleanup deleted a protected run.'
    }
    $repeat = @(& $cleanTemp -TempRoot $temp -Keep $keep 6>&1 | ForEach-Object ToString)
    Assert-Hygiene (@($repeat -match '^REMOVE ').Count -eq 0) 'Temp cleanup is not idempotent.'
}

$temp = New-FixtureDirectory (Join-Path $fixture 'process-runs')
$worker = Join-Path $workspace 'worker.ps1'
'param([string] $Run); Start-Sleep -Seconds 120' | Set-Content -LiteralPath $worker -Encoding UTF8
$runner = (Get-Command powershell.exe).Source
$owned = $untracked = $null
try {
    $path = New-FixtureDirectory (Join-Path $temp ('bzmag-terrain-' + [guid]::NewGuid().ToString('N')))
    $otherPath = New-FixtureDirectory (Join-Path $temp ('bzmag-terrain-' + [guid]::NewGuid().ToString('N')))
    $owned = Start-Process -FilePath $runner -ArgumentList ('-NoProfile -File "{0}" "{1}"' -f $worker, $path) -WindowStyle Hidden -PassThru
    $untracked = Start-Process -FilePath $runner -ArgumentList ('-NoProfile -File "{0}" "{1}"' -f $worker, $otherPath) -WindowStyle Hidden -PassThru
    $record = New-BzmagRunRecord $workspace $path $owned
    $liveLog = Join-Path $path 'godot.log'
    [IO.File]::WriteAllText($liveLog, 'recorded but still in use')
    Complete-BzmagRunRecord $record $liveLog $true
    "$($record.token) $($record.log_sha256)" | Add-Content -LiteralPath $evidence
    $newest = New-FixtureDirectory (Join-Path $temp ('bzmag-terrain-' + [guid]::NewGuid().ToString('N')))
    $newestRecord = New-BzmagRunRecord $workspace $newest $null
    Complete-BzmagRunRecord $newestRecord (Join-Path $newest 'godot.log') $true
    [IO.Directory]::SetLastWriteTimeUtc($path, [DateTime]::UtcNow.AddHours(-1))
    $retention = @(& $cleanTemp -TempRoot $temp -Keep 0 6>&1 | ForEach-Object ToString)
    Assert-Hygiene (@($retention -match "KEEP $($record.token) \(live reference\)").Count -eq 1) 'Cleanup missed a live reference.'
    $shown = @(& $stop -TempRoot $temp 6>&1 | ForEach-Object ToString)
    Assert-Hygiene (@($shown -match "^Owned PID $($owned.Id) ").Count -eq 1 -and
        @($shown -match "^Owned PID $($untracked.Id) ").Count -eq 0) 'Dry run did not distinguish registered and untracked children.'
    Assert-Hygiene (-not $owned.HasExited -and -not $untracked.HasExited) 'The dry run stopped a child.'
    $started = $record.started
    $record.started = '1'
    Write-BzmagRunRecord $record
    $null = & $stop -TempRoot $temp -RunToken $record.token -Apply 6>&1
    Assert-Hygiene (-not $owned.HasExited) 'A stale PID record authorized a stop.'
    $record.started = $started
    Write-BzmagRunRecord $record
    $null = & $stop -TempRoot $temp -RunToken $record.token -Apply 6>&1
    Assert-Hygiene ($owned.WaitForExit(10000) -and -not $untracked.HasExited) 'Apply did not isolate the intended child.'
} finally {
    foreach ($child in $owned,$untracked) {
        if ($child -and -not $child.HasExited) {
            $child.Kill()
            [void]$child.WaitForExit(10000)
        }
    }
}
"PASS: build and temp Keep 0/1/2, dry-run, idempotence, ownership, log retention, and PID reuse ($fixture)"
