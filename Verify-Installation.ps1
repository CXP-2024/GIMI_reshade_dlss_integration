[CmdletBinding()]
param(
    [switch]$LastRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSCommandPath
$manifestPath = Join-Path $root 'package-manifest.sha256'
$statePath = Join-Path $root 'state\launcher-config.json'
$managedIni = Join-Path $root 'state\reshade-runtime\ReShade.ini'
$bridgeConfig = Join-Path $root 'components\DLSS5\Addons\bridge-addons\dlss5-dx11-bridge.cfg'
$bridgeDll = Join-Path $root 'components\Bridge\Dx11FsrBridge.dll'
$optiDll = Join-Path $root 'components\OptiScaler\OptiScaler.dll'
$reShadeDll = Join-Path $root 'components\ReShade\ReShade64.dll'
$dlss5Runtime = Join-Path $root 'components\DLSS5\Addons\bridge-addons\deferred-reno\nvngx_dlssnr.dll'
$dlss5RuntimeSha256 = '4C5BD1171C7336B4B04FB394DE51DA285AB6EAD6F922D7AFDEC163F71C319D74'

function Get-Sha256 {
    param([string]$Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Assert-File {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
}

function Get-IniValue {
    param([string]$Path, [string]$Section, [string]$Key)
    $inSection = $false
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[([^]]+)\]$') {
            $inSection = $Matches[1].Equals($Section, [StringComparison]::OrdinalIgnoreCase)
            continue
        }
        if ($inSection -and $trimmed -match ('^' + [regex]::Escape($Key) + '\s*=\s*(.*)$')) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-KeyValue {
    param([string]$Path, [string]$Key)
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -match ('^' + [regex]::Escape($Key) + '\s*=\s*(.*)$')) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

Assert-File -Path $manifestPath -Label 'Package integrity manifest'
$checked = 0
foreach ($line in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
    $parts = $trimmed.Split('|', 2)
    if ($parts.Count -ne 2 -or $parts[0].Contains('..') -or [IO.Path]::IsPathRooted($parts[0])) {
        throw "Invalid manifest entry: $line"
    }
    $path = Join-Path $root $parts[0]
    Assert-File -Path $path -Label "Manifest component '$($parts[0])'"
    $actual = Get-Sha256 -Path $path
    if (-not $actual.Equals($parts[1].Trim(), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Integrity failure: $($parts[0]) does not match the package manifest. Re-extract the archive."
    }
    $checked++
}
if ($checked -lt 8) { throw 'The package manifest is incomplete.' }
Write-Host "Package integrity: $checked protected files verified." -ForegroundColor Green

Assert-File -Path $dlss5Runtime -Label 'DLSS5 runtime (download it using the links in README.md, then run Install-DLSS5-Runtime.bat)'
$runtimeHash = Get-Sha256 -Path $dlss5Runtime
if (-not $runtimeHash.Equals($dlss5RuntimeSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "DLSS5 runtime hash mismatch. Expected $dlss5RuntimeSha256, got $runtimeHash."
}
Write-Host 'DLSS5 runtime: validated nvngx_dlssnr.dll verified.' -ForegroundColor Green

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Write-Host 'Runtime configuration: not created yet. Run Launch-Genshin-GIMI-DLSS-ReShade.bat once.' -ForegroundColor Yellow
    exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-File -Path $state.GamePath -Label 'Configured GenshinImpact.exe'
Assert-File -Path (Join-Path $state.GimiPath '3DMigoto Loader.exe') -Label 'Configured GIMI Loader'
Assert-File -Path $managedIni -Label 'Managed ReShade configuration'
Assert-File -Path $bridgeConfig -Label 'Managed DLSS5 bridge configuration'

if ((Get-IniValue -Path $managedIni -Section 'RenoDX.DLSS5' -Key 'NREnableUpscaling') -ne '1') {
    throw 'DLSS5 control profile mismatch: NREnableUpscaling must match the original v1.1 value (1).'
}
if ((Get-IniValue -Path $managedIni -Section 'RenoDX.DLSS5' -Key 'NeuralUplift') -ne '1') {
    throw 'DLSS5 configuration is incomplete: NeuralUplift must be enabled.'
}
if ((Get-KeyValue -Path $bridgeConfig -Key 'stage') -ne '3' -or
    (Get-KeyValue -Path $bridgeConfig -Key 'mode') -ne '2' -or
    (Get-KeyValue -Path $bridgeConfig -Key 'skip_game') -ne '1' -or
    (Get-KeyValue -Path $bridgeConfig -Key 'defer_reno') -ne '1') {
    throw 'DLSS5 bridge configuration is not the validated native-NR path.'
}

$fpsConfig = Get-Content -LiteralPath (Join-Path $root 'fps_config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedDllList = @($reShadeDll, $bridgeDll, $optiDll)
if (@($fpsConfig.DllList).Count -ne $expectedDllList.Count -or (@($fpsConfig.DllList) -join '|') -ne ($expectedDllList -join '|')) {
    throw 'UnlockFPS DLL order does not match the validated stable chain.'
}

$sidecar = Join-Path $state.GimiPath 'GIMIHostedReShade.ini'
Assert-File -Path $sidecar -Label 'GIMI hosted ReShade sidecar'
if ((Get-IniValue -Path $sidecar -Section 'HostedReShade' -Key 'Enabled') -ne '1') {
    throw 'GIMI-hosted ReShade is not enabled.'
}

Write-Host 'Runtime configuration: Stable Native NR chain verified.' -ForegroundColor Green
Write-Host '  DLSS is the spatial upscaler; RenoDX runs native-resolution NR; GIMI owns final Present.'

if ($LastRun) {
    $logPath = Join-Path $root 'state\reshade-runtime\ReShade.log'
    Assert-File -Path $logPath -Label 'ReShade log from the last run'
    $log = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
    if ($log -notmatch 'DLSS5 active settings: upscaling=ON' -or
        $log -notmatch 'NR upscaling fell back to native' -or
        $log -notmatch 'feature 18 evaluate failed with 0xbad00005') {
        throw 'Last-run diagnostic is incomplete: the validated v1.1 probe-to-native fallback sequence was not found.'
    }
    $nativeCounts = @([regex]::Matches($log, 'inline feature 18 evaluation succeeded \(count=(\d+),[^\r\n]*\[native\]\)') |
        ForEach-Object { [int64]$_.Groups[1].Value })
    if ($nativeCounts.Count -eq 0 -or ($nativeCounts | Measure-Object -Maximum).Maximum -lt 60) {
        throw 'Last-run diagnostic is incomplete: native NR did not reach 60 successful frames.'
    }
    $maxNativeCount = ($nativeCounts | Measure-Object -Maximum).Maximum
    Write-Host "Last-run diagnostic: continuous native NR verified (reported count: $maxNativeCount+)." -ForegroundColor Green
}
