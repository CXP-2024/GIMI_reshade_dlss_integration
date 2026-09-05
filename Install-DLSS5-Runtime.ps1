[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RuntimePath,
    [ValidateSet('auto', 'rtx30', 'rtx40', 'rtx50')]
    [string]$NrProfile = 'auto',
    [switch]$RequireValidatedHash
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSCommandPath
. (Join-Path $root 'DLSS5-Profiles.ps1')
$statePath = Join-Path $root 'state\launcher-config.json'
$savedProfile = ''
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $saved = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.PSObject.Properties.Name -contains 'NrProfile') {
            $savedProfile = [string]$saved.NrProfile
        }
    } catch { }
}

$resolvedProfile = if ($NrProfile -eq 'auto' -and $savedProfile -in @('rtx30', 'rtx40', 'rtx50')) {
    Write-Host "Using the configured launcher profile: $savedProfile" -ForegroundColor Cyan
    $savedProfile
} else {
    Resolve-Dlss5NrProfile -RequestedProfile $NrProfile -SavedProfile $savedProfile
}
$profile = Get-Dlss5ProfileDefinition -Name $resolvedProfile
$destinationDirectory = Join-Path $root ("components\DLSS5\Addons\{0}" -f $profile.DirectoryName)
$destination = Join-Path $destinationDirectory 'nvngx_dlssnr.dll'
$nrChain = Join-Path $destinationDirectory 'nrchain_nvngx.dll'

if (-not (Test-Path -LiteralPath $nrChain -PathType Leaf)) {
    throw "The $($profile.DisplayName) backend is missing: $nrChain"
}
$nrChainHash = (Get-FileHash -LiteralPath $nrChain -Algorithm SHA256).Hash
if (-not $nrChainHash.Equals([string]$profile.NrChainSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Backend/profile mismatch. Expected nrchain_nvngx.dll $($profile.NrChainSha256), got $nrChainHash."
}

Write-Host "Selected profile: $($profile.DisplayName) [$($profile.SupportLevel)]" -ForegroundColor Cyan
if ($profile.AssetProfile -eq 'rtx50') {
    Write-Host 'RTX 50 runtime download:' -ForegroundColor Cyan
    Write-Host '  International: https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing'
    Write-Host '  China: https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz  (code: qisz)'
} else {
    Write-Host 'RTX 30/40 compatibility runtime source (extract nvngx_dlssnr.dll from the RTX30 profile):' -ForegroundColor Cyan
    Write-Host '  International: https://drive.google.com/file/d/1d-aaUEo_ftRpY7mFCO7zUTugBKg7pW-j/view?usp=sharing'
    Write-Host '  China: https://pan.quark.cn/s/f3e0fa0a9155'
    Write-Host '  Archive password: yuanshenqidong'
}
if ($profile.SupportLevel -eq 'experimental') {
    Write-Host 'WARNING: RTX 40 uses the complete RTX 30 backend/runtime pair for testing.' -ForegroundColor Yellow
    Write-Host 'It is allowed to launch, but NR may be unstable or inactive.' -ForegroundColor Yellow
}
Write-Host ''

if ([string]::IsNullOrWhiteSpace($RuntimePath)) {
    $RuntimePath = Read-Host 'Enter the matching nvngx_dlssnr.dll path (you may drag it into this window)'
}
if ($null -eq $RuntimePath) {
    throw 'No runtime path was supplied.'
}

$RuntimePath = $RuntimePath.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $RuntimePath -PathType Leaf)) {
    throw "File not found: $RuntimePath"
}
if (-not [IO.Path]::GetFileName($RuntimePath).Equals('nvngx_dlssnr.dll', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The selected file must be named nvngx_dlssnr.dll.'
}

$actualSha256 = (Get-FileHash -LiteralPath $RuntimePath -Algorithm SHA256).Hash
if (-not $actualSha256.Equals([string]$profile.RuntimeSha256, [StringComparison]::OrdinalIgnoreCase)) {
    if ($RequireValidatedHash) {
        throw "Runtime hash mismatch. Expected $($profile.RuntimeSha256), got $actualSha256."
    }
    Write-Host "WARNING: This runtime is not the release-validated file for $($profile.DisplayName)." -ForegroundColor Yellow
    Write-Host "  Expected: $($profile.RuntimeSha256)" -ForegroundColor Yellow
    Write-Host "  Selected: $actualSha256" -ForegroundColor Yellow
    Write-Host 'It will be installed as requested, but compatibility is not guaranteed.' -ForegroundColor Yellow
} else {
    Write-Host 'Release-validated runtime/backend pair detected.' -ForegroundColor Green
}

New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
if (-not ([IO.Path]::GetFullPath($RuntimePath)).Equals([IO.Path]::GetFullPath($destination), [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $RuntimePath -Destination $destination -Force
}

Write-Host 'DLSS5 runtime installed:' -ForegroundColor Green
Write-Host "  $destination"
Write-Host "  SHA-256: $actualSha256"
