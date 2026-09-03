[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RuntimePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSCommandPath
$destination = Join-Path $root 'components\DLSS5\Addons\bridge-addons\deferred-reno\nvngx_dlssnr.dll'
$expectedSha256 = '4C5BD1171C7336B4B04FB394DE51DA285AB6EAD6F922D7AFDEC163F71C319D74'

Write-Host 'DLSS5 runtime download:' -ForegroundColor Cyan
Write-Host '  International: https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing'
Write-Host '  China: https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz  (code: qisz)'
Write-Host ''

if ([string]::IsNullOrWhiteSpace($RuntimePath)) {
    $RuntimePath = Read-Host 'Enter the downloaded nvngx_dlssnr.dll path (you may drag it into this window)'
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
if (-not $actualSha256.Equals($expectedSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Runtime hash mismatch. Expected $expectedSha256, got $actualSha256."
}

$destinationDirectory = Split-Path -Parent $destination
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
if (-not ([IO.Path]::GetFullPath($RuntimePath)).Equals([IO.Path]::GetFullPath($destination), [StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $RuntimePath -Destination $destination -Force
}

Write-Host 'DLSS5 runtime installed and SHA-256 verified:' -ForegroundColor Green
Write-Host "  $destination"
