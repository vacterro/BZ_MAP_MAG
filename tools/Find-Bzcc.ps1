[CmdletBinding()]
param(
    [string[]] $SteamRoot,
    [string] $ResultFile
)

$ErrorActionPreference = 'Stop'
if (-not $SteamRoot) {
    $user = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    $native = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Valve\Steam' -ErrorAction SilentlyContinue
    $wow = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue
    $SteamRoot = @($user.SteamPath, $native.InstallPath, $wow.InstallPath)
    if ($user.SteamExe -and [IO.Path]::IsPathRooted($user.SteamExe)) {
        $SteamRoot += Split-Path -Parent $user.SteamExe
    }
    $SteamRoot += @(Get-Process steam -ErrorAction SilentlyContinue |
        Where-Object Path | ForEach-Object { Split-Path -Parent $_.Path })
    if (${env:ProgramFiles(x86)}) { $SteamRoot += Join-Path ${env:ProgramFiles(x86)} 'Steam' }
    if ($env:ProgramFiles) { $SteamRoot += Join-Path $env:ProgramFiles 'Steam' }
}

function Read-ManagedText([string] $File) {
    $item = Get-Item -LiteralPath $File -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer -and $item.Length -le 8MB) {
        Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

$roots = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($root in $SteamRoot) {
    if (-not $root -or -not [IO.Path]::IsPathRooted($root) -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $normal = (Resolve-Path -LiteralPath $root).ProviderPath
    [void]$roots.Add($normal)
    $libraries = Read-ManagedText (Join-Path $normal 'steamapps/libraryfolders.vdf')
    foreach ($match in [regex]::Matches([string]$libraries, '(?m)^\s*"(?:path|[0-9]+)"\s*"((?:[^"\\]|\\.)*)"')) {
        $candidate = $match.Groups[1].Value.Replace('\\', '\')
        if ([IO.Path]::IsPathRooted($candidate) -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            [void]$roots.Add((Resolve-Path -LiteralPath $candidate).ProviderPath)
        }
    }
}

$install = ''
foreach ($root in $roots) {
    $steamapps = Join-Path $root 'steamapps'
    $manifest = Read-ManagedText (Join-Path $steamapps 'appmanifest_624970.acf')
    if (-not $manifest -or $manifest -notmatch '(?im)^\s*"appid"\s*"624970"') { continue }
    $name = [regex]::Match($manifest, '(?im)^\s*"installdir"\s*"([^"\\/:]+)"').Groups[1].Value
    if (-not $name -or $name -in '.', '..') { continue }
    $folder = Join-Path $steamapps ('common/' + $name)
    $exe = Join-Path $folder 'battlezone2.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $folder 'bz2r_res') -PathType Container)) { continue }
    $install = (Resolve-Path -LiteralPath $folder).ProviderPath
    if ((Get-Item -LiteralPath $exe).VersionInfo.FileVersion -eq '2.0.185') { break }
}
if ($ResultFile) { Set-Content -LiteralPath $ResultFile -Value $install -Encoding UTF8 }
if ($install) { $install }
