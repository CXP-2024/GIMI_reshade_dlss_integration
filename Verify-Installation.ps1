[CmdletBinding()]
param(
    [switch]$LastRun,
    [switch]$RequireValidatedDlssNrHash,
    [ValidateSet('auto', 'rtx30', 'rtx40', 'rtx50')]
    [string]$NrProfile = 'auto'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSCommandPath
. (Join-Path $root 'DLSS5-Profiles.ps1')
$manifestPath = Join-Path $root 'package-manifest.sha256'
$statePath = Join-Path $root 'state\launcher-config.json'
$managedIni = Join-Path $root 'state\reshade-runtime\ReShade.ini'
$optiIni = Join-Path $root 'components\OptiScaler\OptiScaler.ini'
$bridgeDll = Join-Path $root 'components\Bridge\Dx11FsrBridge.dll'
$optiDll = Join-Path $root 'components\OptiScaler\OptiScaler.dll'
$reShadeDll = Join-Path $root 'components\ReShade\ReShade64.dll'

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

$state = $null
$savedProfile = ''
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.PSObject.Properties.Name -contains 'NrProfile') {
        $savedProfile = [string]$state.NrProfile
    }
}
$resolvedProfile = if ($NrProfile -eq 'auto' -and $savedProfile -in @('rtx30', 'rtx40', 'rtx50')) {
    $savedProfile
} else {
    Resolve-Dlss5NrProfile -RequestedProfile $NrProfile -SavedProfile $savedProfile
}
$profile = Get-Dlss5ProfileDefinition -Name $resolvedProfile
$preNrDirectory = Join-Path $root ("components\DLSS5\Addons\{0}" -f $profile.DirectoryName)
$preNrConfig = Join-Path $preNrDirectory 'nr_before_sr.ini'
$preNrLog = Join-Path $preNrDirectory 'nr-before-sr.log'
$nrChain = Join-Path $preNrDirectory 'nrchain_nvngx.dll'
$dlss5Runtime = Join-Path $preNrDirectory 'nvngx_dlssnr.dll'

Assert-File -Path $nrChain -Label "$($profile.DisplayName) private NR chain bridge"
$nrChainHash = Get-Sha256 -Path $nrChain
if (-not $nrChainHash.Equals([string]$profile.NrChainSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "DLSS5 backend/profile mismatch. Expected nrchain_nvngx.dll $($profile.NrChainSha256), got $nrChainHash."
}
Assert-File -Path $dlss5Runtime -Label 'DLSS5 runtime (download it using the links in README.md, then run Install-DLSS5-Runtime.bat)'
$runtimeHash = Get-Sha256 -Path $dlss5Runtime
if (-not $runtimeHash.Equals([string]$profile.RuntimeSha256, [StringComparison]::OrdinalIgnoreCase)) {
    if ($RequireValidatedDlssNrHash) {
        throw "DLSS5 runtime hash mismatch. Expected $($profile.RuntimeSha256), got $runtimeHash."
    }
    Write-Host 'DLSS5 runtime: player-supplied hash detected; structural verification will continue.' -ForegroundColor Yellow
    Write-Host "  Release-validated: $($profile.RuntimeSha256)" -ForegroundColor Yellow
    Write-Host "  Installed:        $runtimeHash" -ForegroundColor Yellow
} else {
    Write-Host "DLSS5 runtime: release-validated $($profile.DisplayName) pair verified." -ForegroundColor Green
}
if ($profile.SupportLevel -eq 'experimental') {
    Write-Host 'RTX 40 compatibility: using the RTX 30 backend/runtime pair; launch is allowed but NR is experimental.' -ForegroundColor Yellow
}

if ($null -eq $state) {
    Write-Host 'Runtime configuration: not created yet. Run Launch-Genshin-GIMI-DLSS-ReShade.bat once.' -ForegroundColor Yellow
    exit 0
}

Assert-File -Path $state.GamePath -Label 'Configured Genshin Impact game executable'
$configuredGameName = [IO.Path]::GetFileName([string]$state.GamePath)
if ($configuredGameName -notin @('YuanShen.exe', 'GenshinImpact.exe')) {
    throw "Configured game executable must be YuanShen.exe or GenshinImpact.exe: $($state.GamePath)"
}
Assert-File -Path (Join-Path $state.GimiPath '3DMigoto Loader.exe') -Label 'Configured GIMI Loader'
$gimiIni = Join-Path $state.GimiPath 'd3dx.ini'
Assert-File -Path $gimiIni -Label 'Configured GIMI d3dx.ini'
$gimiTarget = Get-IniValue -Path $gimiIni -Section 'Loader' -Key 'target'
if ([string]::IsNullOrWhiteSpace($gimiTarget) -or
    -not $gimiTarget.Trim().Trim('"').Equals($configuredGameName, [StringComparison]::OrdinalIgnoreCase)) {
    throw "GIMI Loader target '$gimiTarget' does not match the configured game executable '$configuredGameName'. Run Configure-Again.bat."
}
Assert-File -Path $managedIni -Label 'Managed ReShade configuration'
Assert-File -Path $preNrConfig -Label 'DLSS5 pre-NR configuration'
Assert-File -Path $optiIni -Label 'OptiScaler configuration'

$nrEnabled = Get-IniValue -Path $preNrConfig -Section 'NRBeforeSR' -Key 'Enabled'
$nrMode = Get-IniValue -Path $preNrConfig -Section 'NRBeforeSR' -Key 'Mode'
if ($nrEnabled -notin @('0', '1') -or $nrMode -notin @('1', '2') -or
    (Get-IniValue -Path $preNrConfig -Section 'NRBeforeSR' -Key 'RetryOriginalOnSRFailure') -ne '1') {
    throw 'DLSS5 profile must use Enabled=0/1, Mode=1/2, and the original-SR failure fallback.'
}
if ($nrEnabled -eq '0') {
    Write-Host 'DLSS5 Feature 18 is currently disabled by the saved F6 state; configuration is otherwise valid.' -ForegroundColor Yellow
}
if ((Get-IniValue -Path $managedIni -Section 'ADDON' -Key 'AddonPath') -ne $preNrDirectory) {
    throw 'Managed ReShade AddonPath does not match the selected GPU/NR profile. Run Configure-Again.bat.'
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
if (-not ([IO.Path]::GetFullPath([string]$fpsConfig.GamePath)).Equals(
        [IO.Path]::GetFullPath([string]$state.GamePath), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'UnlockFPS GamePath does not match the configured game executable. Run Configure-Again.bat.'
}
$expectedDllList = @($reShadeDll, $bridgeDll, $optiDll)
if (@($fpsConfig.DllList).Count -ne $expectedDllList.Count -or (@($fpsConfig.DllList) -join '|') -ne ($expectedDllList -join '|')) {
    throw 'UnlockFPS DLL order does not match the validated stable chain.'
}

$sidecar = Join-Path $state.GimiPath 'GIMIHostedReShade.ini'
Assert-File -Path $sidecar -Label 'GIMI hosted ReShade sidecar'
if ((Get-IniValue -Path $sidecar -Section 'HostedReShade' -Key 'Enabled') -ne '1') {
    throw 'GIMI-hosted ReShade is not enabled.'
}

$modeDescription = if ($nrMode -eq '1') {
    'original DLSS SR -> output-resolution DLSS5 NR'
} else {
    'render-resolution DLSS5 NR -> original DLSS SR'
}
Write-Host "Runtime configuration: Mode $nrMode ($modeDescription) verified for $($profile.DisplayName)." -ForegroundColor Green
Write-Host '  GIMI owns final Present; hosted ReShade remains downstream of the selected NR/SR chain.'

if ($LastRun) {
    Assert-File -Path $preNrLog -Label 'DLSS5 pre-NR log from the last run'
    $log = Get-Content -LiteralPath $preNrLog -Raw -Encoding UTF8
    if ($log -match 'signed feature 18 evaluate failed|Feature 18 create rejected|AI upscaling chain rejected|NR runtime exports incomplete|signed feature 18 disabled') {
        throw 'Last-run diagnostic failed: the low-resolution NR request was rejected.'
    }
    if ($log -notmatch 'signed DLSSNR D3D12 runtime initialized through nrchain_nvngx\.dll') {
        throw 'Last-run diagnostic failed: the signed DLSSNR runtime did not initialize through the private bridge.'
    }

    $srEval = [regex]::Match($log, 'SuperSampling Evaluate #\d+ handle=\S+ create=(?<inW>\d+)x(?<inH>\d+) -> (?<outW>\d+)x(?<outH>\d+)')
    if (-not $srEval.Success) {
        throw 'Last-run diagnostic failed: no original DLSS SuperSampling evaluation was found.'
    }
    $srInW = [int]$srEval.Groups['inW'].Value
    $srInH = [int]$srEval.Groups['inH'].Value
    $srOutW = [int]$srEval.Groups['outW'].Value
    $srOutH = [int]$srEval.Groups['outH'].Value
    if ($srOutW -le $srInW -and $srOutH -le $srInH) {
        throw "Last-run diagnostic failed: Feature 1 did not upscale ($srInW x $srInH -> $srOutW x $srOutH)."
    }

    if ($nrMode -eq '2') {
        $nrCreate = [regex]::Match($log, 'signed feature 18 create (?<inW>\d+)x(?<inH>\d+) -> (?<outW>\d+)x(?<outH>\d+) result=0x00000001\(Success\)')
        if (-not $nrCreate.Success) {
            throw 'Last-run diagnostic failed: no successful render-resolution Feature 18 creation contract was found.'
        }
        $nrInW = [int]$nrCreate.Groups['inW'].Value
        $nrInH = [int]$nrCreate.Groups['inH'].Value
        $nrOutW = [int]$nrCreate.Groups['outW'].Value
        $nrOutH = [int]$nrCreate.Groups['outH'].Value
        if ($nrInW -ne $nrOutW -or $nrInH -ne $nrOutH -or $srInW -ne $nrInW -or $srInH -ne $nrInH) {
            throw "Last-run diagnostic failed: Mode 2 extents disagree (Feature 18 $nrInW x $nrInH -> $nrOutW x $nrOutH; Feature 1 $srInW x $srInH -> $srOutW x $srOutH)."
        }
        $nrSuccessIndex = $log.IndexOf('NR-before-SR evaluate succeeded', [StringComparison]::Ordinal)
        if ($nrSuccessIndex -lt 0 -or $log.IndexOf('nvngx_dlss EvaluateFeature reached', $nrSuccessIndex, [StringComparison]::Ordinal) -lt 0) {
            throw 'Last-run diagnostic failed: a successful pre-NR evaluation was not followed by original DLSS SR.'
        }
        Write-Host 'Last-run diagnostic: render-resolution NR succeeded before the original DLSS SR pass.' -ForegroundColor Green
        Write-Host "  Feature 18: $nrInW x $nrInH -> $nrOutW x $nrOutH; Feature 1: $srInW x $srInH -> $srOutW x $srOutH."
    } else {
        $postCreate = [regex]::Match($log, 'post-SR signed feature 18 create (?<outW>\d+)x(?<outH>\d+) guides=(?<guideW>\d+)x(?<guideH>\d+) result=0x00000001\(Success\)')
        if (-not $postCreate.Success) {
            throw 'Last-run diagnostic failed: no successful output-resolution Feature 18 creation contract was found.'
        }
        $nrOutW = [int]$postCreate.Groups['outW'].Value
        $nrOutH = [int]$postCreate.Groups['outH'].Value
        $guideW = [int]$postCreate.Groups['guideW'].Value
        $guideH = [int]$postCreate.Groups['guideH'].Value
        if ($nrOutW -ne $srOutW -or $nrOutH -ne $srOutH -or $guideW -ne $srInW -or $guideH -ne $srInH) {
            throw "Last-run diagnostic failed: Mode 1 extents disagree (Feature 1 $srInW x $srInH -> $srOutW x $srOutH; Feature 18 $nrOutW x $nrOutH, guides $guideW x $guideH)."
        }
        if ($log.IndexOf('NR-after-SR evaluate succeeded', [StringComparison]::Ordinal) -lt 0) {
            throw 'Last-run diagnostic failed: no successful post-SR NR evaluation was found.'
        }
        Write-Host 'Last-run diagnostic: original DLSS SR succeeded before output-resolution NR.' -ForegroundColor Green
        Write-Host "  Feature 1: $srInW x $srInH -> $srOutW x $srOutH; Feature 18: $nrOutW x $nrOutH with $guideW x $guideH guides."
    }
}
