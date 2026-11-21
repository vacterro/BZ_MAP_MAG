[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Godot,
    [Parameter(Mandatory)] [string] $Mission,
    [string] $Game = '-',
    [string] $VrvSource = '-'
)

$ErrorActionPreference = 'Stop'
if (Get-Process battlezone2 -ErrorAction SilentlyContinue) { throw 'Close any existing Battlezone session before this test.' }
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'app'
$mission = (Resolve-Path -LiteralPath $Mission).Path
$run = (New-Item -ItemType Directory -Path (Join-Path $repo ('build/ui-bridge-' + [guid]::NewGuid().ToString('N'))) -Force).FullName
$log = Join-Path $run 'bridge.log'
$documents = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games/Battlezone Combat Commander'
$previous = @(Get-ChildItem -LiteralPath $documents -Filter 'Battlezone*.log' | ForEach-Object Name)
$arguments = "--headless --path `"$app`" --script res://tests/playtest_session.gd --log-file `"$log`" -- `"$mission`" `"$Game`" `"$VrvSource`" `"$run`""
$driver = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(30)
$runtime = $null
$gameFolder = $null
try {
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $log) {
            $reported = Select-String -LiteralPath $log -Pattern '^GAME PID ([0-9]+)$' | Select-Object -First 1
            if ($reported) {
                $runtime = Get-Process -Id ([int]$reported.Matches[0].Groups[1].Value) -ErrorAction SilentlyContinue |
                    Where-Object { $_.Path -like (Join-Path $env:TEMP 'bzm/BZMAG-*/game/battlezone2.exe') }
            }
        }
        $logEntry = Get-ChildItem -LiteralPath $documents -Filter 'Battlezone*.log' |
            Where-Object Name -NotIn $previous | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($runtime -and $logEntry -and (Select-String -LiteralPath $logEntry.FullName -Pattern 'Entering run code \[RUN\]' -Quiet)) { break }
        if ($driver.HasExited -or ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern '^SCRIPT ERROR:' -Quiet))) { break }
        Start-Sleep -Milliseconds 200
    }
    $name = Split-Path -Leaf $mission
    if (-not $runtime -or -not $logEntry -or -not (Select-String -LiteralPath $logEntry.FullName -SimpleMatch "Loaded from file $name" -Quiet)) {
        if ($logEntry) { Get-Content -LiteralPath $logEntry.FullName -Tail 16 }
        throw 'The one-click scenario did not reach the edited mission.'
    }
    $gameFolder = Split-Path -Parent $runtime.Path
    Select-String -LiteralPath $logEntry.FullName -Pattern 'Terrain Loaded|Loaded from file|Entering run code \[MISSION\]|Entering run code \[RUN\]' |
        ForEach-Object Line | Set-Content -LiteralPath (Join-Path $run 'engine.log') -Encoding UTF8
} finally {
    if ($runtime) {
        $null = $runtime.CloseMainWindow()
        $null = $runtime.WaitForExit(9000)
    }
    if (-not $driver.WaitForExit(12000)) { $driver.Kill() }
    $run
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 25 }
}
if ($driver.ExitCode -ne 0) { throw 'Playtest did not return control to the editor.' }
if (Test-Path -LiteralPath $gameFolder) { throw 'Temporary native snapshot survived a normal exit.' }
Get-Content -LiteralPath (Join-Path $run 'engine.log')
