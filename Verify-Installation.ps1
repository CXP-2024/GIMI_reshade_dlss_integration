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
$preNrConfig = Join-Path $root 'components\DLSS5\Addons\pre-nr\nr_before_sr.ini'
$preNrLog = Join-Path $root 'components\DLSS5\Addons\pre-nr\nr-before-sr.log'
$optiIni = Join-Path $root 'components\OptiScaler\OptiScaler.ini'
$bridgeDll = Join-Path $root 'components\Bridge\Dx11FsrBridge.dll'
$optiDll = Join-Path $root 'components\OptiScaler\OptiScaler.dll'
$reShadeDll = Join-Path $root 'components\ReShade\ReShade64.dll'
$dlss5Runtime = Join-Path $root 'components\DLSS5\Addons\pre-nr\nvngx_dlssnr.dll'
$dlss5RuntimeSha256 = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'

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
if ($checked -lt 10) { throw 'The package manifest is incomplete.' }
Write-Host "Package integrity: $checked protected files verified." -ForegroundColor Green

Assert-File -Path $dlss5Runtime -Label 'DLSS5 runtime (download it using the links in README.md, then run Install-DLSS5-Runtime.bat)'
$runtimeHash = Get-Sha256 -Path $dlss5Runtime
if (-not $runtimeHash.Equals($dlss5RuntimeSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "DLSS5 runtime hash mismatch. Expected $dlss5RuntimeSha256, got $runtimeHash."
}
Write-Host 'DLSS5 runtime: validated pre-NR nvngx_dlssnr.dll verified.' -ForegroundColor Green

if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    Write-Host 'Runtime configuration: not created yet. Run Launch-Genshin-GIMI-DLSS-ReShade.bat once.' -ForegroundColor Yellow
    exit 0
}

$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-File -Path $state.GamePath -Label 'Configured GenshinImpact.exe'
Assert-File -Path (Join-Path $state.GimiPath '3DMigoto Loader.exe') -Label 'Configured GIMI Loader'
Assert-File -Path $managedIni -Label 'Managed ReShade configuration'
Assert-File -Path $preNrConfig -Label 'DLSS5 pre-NR configuration'
Assert-File -Path $optiIni -Label 'OptiScaler configuration'

if ((Get-IniValue -Path $preNrConfig -Section 'NRBeforeSR' -Key 'Enabled') -ne '1' -or
    (Get-IniValue -Path $preNrConfig -Section 'NRBeforeSR' -Key 'Mode') -ne '2' -or
    (Get-IniValue -Path $preNrConfig -Section 'NRBeforeSR' -Key 'RetryOriginalOnSRFailure') -ne '1') {
    throw 'DLSS5 pre-NR profile must be enabled in Mode 2 with the original-SR fallback.'
}
if ((Get-IniValue -Path $optiIni -Section 'Upscalers' -Key 'Dx11Upscaler') -ne 'dlss_12' -or
    (Get-IniValue -Path $optiIni -Section 'Inputs' -Key 'EnableFsr2Inputs') -ne 'true' -or
    (Get-IniValue -Path $optiIni -Section 'Inputs' -Key 'UseFsr2Inputs') -ne 'true' -or
    (Get-IniValue -Path $optiIni -Section 'Inputs' -Key 'UseFsr2Dx11Inputs') -ne 'true' -or
    (Get-IniValue -Path $optiIni -Section 'Hooks' -Key 'SkipD3D11DeviceVTableHooks') -ne 'true') {
    throw 'OptiScaler is not pinned to the Genshin FSR2-DX11 -> DLSS-on-DX12 path.'
}
if ((Get-IniValue -Path $optiIni -Section 'DlssNr' -Key 'Enabled') -ne 'false' -or
    (Get-IniValue -Path $optiIni -Section 'Plugins' -Key 'LoadReShade') -ne 'false') {
    throw 'Conflicting OptiScaler post-NR or ReShade ownership is enabled.'
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

Write-Host 'Runtime configuration: pre-NR -> original DLSS SR chain verified.' -ForegroundColor Green
Write-Host '  DLSS5 runs at render resolution, original DLSS performs final upscaling, and GIMI owns final Present.'

if ($LastRun) {
    Assert-File -Path $preNrLog -Label 'DLSS5 pre-NR log from the last run'
    $log = Get-Content -LiteralPath $preNrLog -Raw -Encoding UTF8
    if ($log -match 'signed feature 18 evaluate failed|Feature 18 create rejected|AI upscaling chain rejected|NR runtime exports incomplete|signed feature 18 disabled') {
        throw 'Last-run diagnostic failed: the low-resolution NR request was rejected.'
    }
    if ($log -notmatch 'signed DLSSNR D3D12 runtime initialized through nrchain_nvngx\.dll') {
        throw 'Last-run diagnostic failed: the signed DLSSNR runtime did not initialize through the private bridge.'
    }

    $nrCreate = [regex]::Match($log, 'signed feature 18 create (?<inW>\d+)x(?<inH>\d+) -> (?<outW>\d+)x(?<outH>\d+) result=0x00000001\(Success\)')
    if (-not $nrCreate.Success) {
        throw 'Last-run diagnostic failed: no successful Feature 18 creation contract was found.'
    }
    $nrInW = [int]$nrCreate.Groups['inW'].Value
    $nrInH = [int]$nrCreate.Groups['inH'].Value
    $nrOutW = [int]$nrCreate.Groups['outW'].Value
    $nrOutH = [int]$nrCreate.Groups['outH'].Value
    if ($nrInW -ne $nrOutW -or $nrInH -ne $nrOutH) {
        throw "Last-run diagnostic failed: Feature 18 was not a render-resolution 1:1 pass ($nrInW x $nrInH -> $nrOutW x $nrOutH)."
    }

    $fp16Color = [regex]::Match($log, "Color\s+=\s+\S+ physical=$($nrInW)x$($nrInH) format=10\(R16G16B16A16_FLOAT\)")
    if (-not $fp16Color.Success) {
        throw 'Last-run diagnostic failed: Feature 18 did not receive the validated FP16 render-resolution Color resource.'
    }

    $srEval = [regex]::Match($log, 'SuperSampling Evaluate #\d+ handle=\S+ create=(?<inW>\d+)x(?<inH>\d+) -> (?<outW>\d+)x(?<outH>\d+)')
    if (-not $srEval.Success) {
        throw 'Last-run diagnostic failed: no original DLSS SuperSampling evaluation was found.'
    }
    $srInW = [int]$srEval.Groups['inW'].Value
    $srInH = [int]$srEval.Groups['inH'].Value
    $srOutW = [int]$srEval.Groups['outW'].Value
    $srOutH = [int]$srEval.Groups['outH'].Value
    if ($srInW -ne $nrInW -or $srInH -ne $nrInH -or ($srOutW -le $srInW -and $srOutH -le $srInH)) {
        throw "Last-run diagnostic failed: Feature 1 did not upscale the same render extent ($srInW x $srInH -> $srOutW x $srOutH)."
    }

    $nrSuccessIndex = $log.IndexOf('NR-before-SR evaluate succeeded', [StringComparison]::Ordinal)
    if ($nrSuccessIndex -lt 0) {
        throw 'Last-run diagnostic is incomplete: no successful render-resolution NR evaluation was found.'
    }
    if ($log.IndexOf('nvngx_dlss EvaluateFeature reached', $nrSuccessIndex, [StringComparison]::Ordinal) -lt 0) {
        throw 'Last-run diagnostic failed: the original DLSS pass did not follow the successful pre-NR evaluation.'
    }
    Write-Host 'Last-run diagnostic: render-resolution NR succeeded before the original DLSS SR pass.' -ForegroundColor Green
    Write-Host "  Feature 18: $nrInW x $nrInH -> $nrOutW x $nrOutH; Feature 1: $srInW x $srInH -> $srOutW x $srOutH."
}
