[CmdletBinding()]
param([switch]$Force)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSCommandPath))
$configPath = Join-Path $root 'fps_config.json'
$stagedDll = Join-Path $root 'GIMI\d3d11.dll'

function Read-JsonConfig {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Set-JsonProperty([object]$Object, [string]$Name, [object]$Value) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
    else { $property.Value = $Value }
}

function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

function Read-GamePath {
    while ($true) {
        $value = Read-Host 'Enter full path to GenshinImpact.exe or YuanShen.exe (blank to cancel)'
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        $value = $value.Trim().Trim('"')
        if (-not (Test-Path -LiteralPath $value -PathType Leaf)) {
            Write-Host 'File not found. Try again.' -ForegroundColor Yellow
            continue
        }
        $name = [IO.Path]::GetFileName($value)
        if ($name -ine 'GenshinImpact.exe' -and $name -ine 'YuanShen.exe') {
            Write-Host 'The file name must be GenshinImpact.exe or YuanShen.exe.' -ForegroundColor Yellow
            continue
        }
        return [IO.Path]::GetFullPath($value)
    }
}

function Read-GimiPath {
    while ($true) {
        $value = Read-Host 'Enter full path to the GIMI 3dmigoto folder (blank to cancel)'
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        $value = [IO.Path]::GetFullPath($value.Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath (Join-Path $value 'd3dx.ini') -PathType Leaf)) {
            Write-Host 'd3dx.ini was not found. Try again.' -ForegroundColor Yellow
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $value 'Mods') -PathType Container)) {
            Write-Host 'Mods folder was not found. Try again.' -ForegroundColor Yellow
            continue
        }
        return $value
    }
}

function Read-OptionalReshadePath {
    while ($true) {
        $value = Read-Host 'Enter full path to ReShade64.dll (blank to skip ReShade)'
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        $value = $value.Trim().Trim('"')
        if (-not (Test-Path -LiteralPath $value -PathType Leaf)) {
            Write-Host 'ReShade DLL was not found. Try again or press Enter to skip.' -ForegroundColor Yellow
            continue
        }
        if ([IO.Path]::GetFileName($value) -ine 'ReShade64.dll') {
            Write-Host 'The file name must be ReShade64.dll.' -ForegroundColor Yellow
            continue
        }
        return [IO.Path]::GetFullPath($value)
    }
}

try {
    $existing = Read-JsonConfig
    $savedDll = ''
    if ($null -ne $existing -and $null -ne $existing.PSObject.Properties['PreloadDlls']) {
        $savedDlls = @($existing.PreloadDlls)
        if ($savedDlls.Count -gt 0) { $savedDll = [string]$savedDlls[0] }
    }
    $validSaved = $null -ne $existing -and
        -not [string]::IsNullOrWhiteSpace([string]$existing.GamePath) -and
        (Test-Path -LiteralPath ([string]$existing.GamePath) -PathType Leaf) -and
        -not [string]::IsNullOrWhiteSpace($savedDll) -and
        (Test-Path -LiteralPath $savedDll -PathType Leaf)
    if (-not $Force -and $validSaved) { exit 0 }

    Write-Host ''
    Write-Host 'GIMI + UnlockFPS setup' -ForegroundColor Cyan
    Write-Host 'Enter paths exactly as shown in Explorer. Press Enter on an empty line to cancel.'
    $gamePath = Read-GamePath
    if ([string]::IsNullOrWhiteSpace($gamePath)) { exit 2 }
    $gimiPath = Read-GimiPath
    if ([string]::IsNullOrWhiteSpace($gimiPath)) { exit 2 }
    $reshadePath = Read-OptionalReshadePath
    if (-not (Test-Path -LiteralPath $stagedDll -PathType Leaf)) { throw "Missing staged DLL: $stagedDll" }

    $targetDll = Join-Path $gimiPath 'd3d11.dll'
    $stagedHash = Get-Sha256 $stagedDll
    $targetHash = if (Test-Path -LiteralPath $targetDll -PathType Leaf) { Get-Sha256 $targetDll } else { '' }
    if ($stagedHash -ine $targetHash) {
        if (Test-Path -LiteralPath $targetDll -PathType Leaf) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Copy-Item -LiteralPath $targetDll -Destination (Join-Path $gimiPath "d3d11.dll.before-integration-$stamp") -Force
        }
        Copy-Item -LiteralPath $stagedDll -Destination $targetDll -Force
    }

    if ($null -eq $existing) {
        $existing = [pscustomobject][ordered]@{
            GamePath = ''; AutoStart = $true; AutoClose = $true; PopupWindow = $true
            Fullscreen = $false; UseCustomRes = $false; IsExclusiveFullscreen = $false; StartMinimized = $true
            UsePowerSave = $false; SuspendLoad = $false; UseMobileUI = $false; UseHDR = $true; FPSTarget = 160
            CustomResX = 1920; CustomResY = 1080; MonitorNum = 1; Priority = 3; AdditionalCommandLine = ''
            LastVersionNotify = 0; PreloadDlls = @(); GimiLoaderPath = ''; DllList = @()
        }
    }
    Set-JsonProperty $existing 'GamePath' $gamePath
    Set-JsonProperty $existing 'PreloadDlls' @($targetDll)
    Set-JsonProperty $existing 'GimiLoaderPath' ''
    Set-JsonProperty $existing 'UseHDR' $true
    if ($null -ne $reshadePath) { Set-JsonProperty $existing 'DllList' @($reshadePath) }
    else { Set-JsonProperty $existing 'DllList' @() }
    $existing | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

    Write-Host ''
    Write-Host 'Configuration saved. Starting UnlockFPS...' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
