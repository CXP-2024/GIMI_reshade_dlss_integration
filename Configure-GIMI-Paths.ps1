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

function Read-OptionalDlssRuntime {
    while ($true) {
        $value = Read-Host 'Enter full path to the Genshin FSR Bridge folder for DLSS (blank to skip DLSS)'
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        try { $value = [IO.Path]::GetFullPath($value.Trim().Trim('"')) }
        catch {
            Write-Host 'The path is invalid. Try again or press Enter to skip.' -ForegroundColor Yellow
            continue
        }

        $bridgeDll = Join-Path $value 'payload\Bridge\Dx11FsrBridge.dll'
        $bridgeIni = Join-Path $value 'payload\Bridge\Dx11FsrBridge.ini'
        $optiDll = Join-Path $value 'payload\OptiScaler\OptiScaler.dll'
        $optiIni = Join-Path $value 'payload\OptiScaler\OptiScaler.ini'
        $dlssDll = Join-Path $value 'payload\OptiScaler\nvngx_dlss.dll'
        $missing = @($bridgeDll, $bridgeIni, $optiDll, $optiIni, $dlssDll) | Where-Object {
            -not (Test-Path -LiteralPath $_ -PathType Leaf)
        }
        if (@($missing).Count -gt 0) {
            Write-Host 'This is not a complete FSR Bridge + OptiScaler + NVIDIA DLSS runtime. Try again or press Enter to skip.' -ForegroundColor Yellow
            continue
        }

        return [pscustomobject]@{
            Root = $value
            BridgeDll = [IO.Path]::GetFullPath($bridgeDll)
            OptiScalerDll = [IO.Path]::GetFullPath($optiDll)
            OptiScalerIni = [IO.Path]::GetFullPath($optiIni)
        }
    }
}

function Set-IniValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $lines = [Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]][IO.File]::ReadAllLines($Path))
    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*\[(?<section>[^\]]+)\]\s*$') {
            if ($sectionStart -ge 0) {
                $sectionEnd = $index
                break
            }
            if ($Matches.section -ieq $Section) { $sectionStart = $index }
        }
    }
    if ($sectionStart -lt 0) { throw "Missing [$Section] section in $Path" }

    $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($index = $sectionStart + 1; $index -lt $sectionEnd; $index++) {
        if ($lines[$index] -match $keyPattern) {
            if ($lines[$index] -ieq "$Key = $Value") { return $false }
            $lines[$index] = "$Key = $Value"
            $encoding = [Text.UTF8Encoding]::new($false)
            [IO.File]::WriteAllLines($Path, [string[]]$lines, $encoding)
            return $true
        }
    }

    $lines.Insert($sectionEnd, "$Key = $Value")
    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllLines($Path, [string[]]$lines, $encoding)
    return $true
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
    if ($validSaved -and $null -ne $existing.PSObject.Properties['DllList']) {
        foreach ($dll in @($existing.DllList)) {
            if ([string]::IsNullOrWhiteSpace([string]$dll) -or -not (Test-Path -LiteralPath ([string]$dll) -PathType Leaf)) {
                $validSaved = $false
                break
            }
        }
    }
    if (-not $Force -and $validSaved) { exit 0 }

    Write-Host ''
    Write-Host 'GIMI + ReShade + DLSS + UnlockFPS setup' -ForegroundColor Cyan
    Write-Host 'Enter paths exactly as shown in Explorer. Press Enter on an empty line to cancel.'
    $gamePath = Read-GamePath
    if ([string]::IsNullOrWhiteSpace($gamePath)) { exit 2 }
    $gimiPath = Read-GimiPath
    if ([string]::IsNullOrWhiteSpace($gimiPath)) { exit 2 }
    $reshadePath = Read-OptionalReshadePath
    $dlssRuntime = Read-OptionalDlssRuntime
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
    $dllList = [Collections.Generic.List[string]]::new()
    if ($null -ne $reshadePath) { $dllList.Add($reshadePath) }
    if ($null -ne $dlssRuntime) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $optiBackup = "$($dlssRuntime.OptiScalerIni).before-dlss-$stamp"
        Copy-Item -LiteralPath $dlssRuntime.OptiScalerIni -Destination $optiBackup -Force
        $changed = Set-IniValue -Path $dlssRuntime.OptiScalerIni -Section 'Upscalers' -Key 'Dx11Upscaler' -Value 'dlss'
        if ($changed) {
            Write-Host "Configured OptiScaler to use DLSS. Backup: $optiBackup" -ForegroundColor DarkGray
        }
        else {
            Write-Host "OptiScaler is already configured to use DLSS. Backup: $optiBackup" -ForegroundColor DarkGray
        }
        # OptiScaler scans the executable only at its startup, so Bridge must load first.
        $dllList.Add($dlssRuntime.BridgeDll)
        $dllList.Add($dlssRuntime.OptiScalerDll)
    }
    Set-JsonProperty $existing 'DllList' @($dllList)
    $existing | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8

    Write-Host ''
    if ($null -ne $dlssRuntime) {
        Write-Host 'DLSS chain saved: GIMI -> ReShade (optional) -> Bridge -> OptiScaler.' -ForegroundColor Green
    }
    Write-Host 'Configuration saved. Starting UnlockFPS...' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}
