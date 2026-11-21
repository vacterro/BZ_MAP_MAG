function Write-BzmagJsonFile([string] $Path, $Value) {
    $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $temporary = $destination + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Value -Depth 5 -Compress))
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                if ([IO.File]::Exists($destination)) {
                    [IO.File]::Replace($temporary, $destination, [NullString]::Value)
                } else {
                    [IO.File]::Move($temporary, $destination)
                }
                return
            } catch [IO.IOException] {
                if ($attempt -eq 4) { throw }
                Start-Sleep -Milliseconds 15
            }
        }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Write-BzmagRunRecord($Record) {
    Write-BzmagJsonFile (Join-Path $Record.run '.bzmag-run.json') $Record
}

function Get-BzmagFileSha256([string] $Path) {
    $stream = [IO.File]::OpenRead($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($digest.ComputeHash($stream)).Replace('-', '')
    } finally {
        $digest.Dispose()
        $stream.Dispose()
    }
}

function New-BzmagRunRecord([string] $Workspace, [string] $Run, $Process) {
    $record = [pscustomobject]@{
        schema = 1
        workspace = (Resolve-Path -LiteralPath $Workspace).Path
        run = (Resolve-Path -LiteralPath $Run).Path
        token = Split-Path -Leaf $Run
        process_id = 0
        started = ''
        executable = ''
        verdict = 'UNKNOWN'
        log_sha256 = ''
    }
    try {
        if ($Process -is [Diagnostics.Process] -and -not $Process.HasExited) {
            $record.started = $Process.StartTime.ToFileTimeUtc().ToString()
            $record.executable = $Process.Path
            $record.process_id = $Process.Id
        }
    } catch [InvalidOperationException] {
        # A fast child may exit before its identity is read.
    }
    Write-BzmagRunRecord $record
    return $record
}

function Complete-BzmagRunRecord($Record, [string] $Log, [bool] $Ok) {
    $Record.verdict = if ($Ok) { 'PASS' } else { 'FAIL' }
    if (Test-Path -LiteralPath $Log -PathType Leaf) {
        $Record.log_sha256 = Get-BzmagFileSha256 $Log
    }
    Write-BzmagRunRecord $Record
}

function Read-BzmagRunRecord([IO.DirectoryInfo] $Directory, [string] $Workspace) {
    if ($Directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { return }
    $marker = Get-Item -LiteralPath (Join-Path $Directory.FullName '.bzmag-run.json') -Force -ErrorAction SilentlyContinue
    if (-not $marker -or $marker.PSIsContainer -or $marker.Length -gt 8192 -or
        ($marker.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return }
    try {
        $record = Get-Content -LiteralPath $marker.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch { return }
    if ($record -is [pscustomobject] -and $record.schema -eq 1 -and $record.workspace -eq $Workspace -and
        $record.run -eq $Directory.FullName -and $record.token -eq $Directory.Name) {
        return $record
    }
}

function Test-BzmagPathReference([string] $Value, [string] $Run) {
    if (-not $Value) { return $false }
    $path = [regex]::Escape($Run.Replace('/', '\').TrimEnd('\'))
    return $Value.Replace('/', '\') -match "(?i)$path(?:\\|""|'|\s|$)"
}
