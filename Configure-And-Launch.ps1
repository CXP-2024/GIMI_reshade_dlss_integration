[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$GimiPath,
    [switch]$ConfigureOnly,
    [switch]$ForceConfigure,
    [switch]$RequireValidatedDlssNrHash,
    [ValidateSet('PreNRThenDLSS')]
    [string]$TestProfile = 'PreNRThenDLSS'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSCommandPath
$stateDirectory = Join-Path $root 'state'
$statePath = Join-Path $stateDirectory 'launcher-config.json'
$unlockerPath = Join-Path $root 'unlockfps_nc.exe'
$gimiSourceDll = Join-Path $root 'GIMI\d3d11.dll'
$bridgeDll = Join-Path $root 'components\Bridge\Dx11FsrBridge.dll'
$optiDirectory = Join-Path $root 'components\OptiScaler'
$optiDll = Join-Path $optiDirectory 'OptiScaler.dll'
$nvngxDlssDll = Join-Path $optiDirectory 'nvngx_dlss.dll'
$optiTemplate = Join-Path $optiDirectory 'OptiScaler.template.ini'
$reShadeDirectory = Join-Path $root 'components\ReShade'
$reShadeDll = Join-Path $reShadeDirectory 'ReShade64.dll'
$reShadeIniTemplate = Join-Path $reShadeDirectory 'ReShade.ini'
$reShadePreset = Join-Path $reShadeDirectory 'ReShadePreset.ini'
$dlss5AddonDirectory = Join-Path $root 'components\DLSS5\Addons'
$dlss5BridgeAddonDirectory = Join-Path $dlss5AddonDirectory 'pre-nr'
$dlss5BridgeAddon = Join-Path $dlss5BridgeAddonDirectory 'nr-before-sr.zh-CN.addon64'
$dlss5NrChainBridge = Join-Path $dlss5BridgeAddonDirectory 'nrchain_nvngx.dll'
$dlss5Runtime = Join-Path $dlss5BridgeAddonDirectory 'nvngx_dlssnr.dll'
$dlss5RuntimeSha256 = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
$dlss5RuntimeGoogleDrive = 'https://drive.google.com/file/d/1L7Pi4adSQal_OxpEzTMuT0NfeQTKIK-_/view?usp=sharing'
$dlss5RuntimeBaidu = 'https://pan.baidu.com/s/1SAm1-QL0YvH8Kc28OGigAA?pwd=qisz'
$manifestPath = Join-Path $root 'package-manifest.sha256'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Test-Dlss5Profile {
    param([string]$Profile)
    return $Profile -eq 'PreNRThenDLSS'
}

function Write-Status {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    Write-Host $Message -ForegroundColor $Color
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Assert-File {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
}

function Get-Sha256 {
    param([string]$Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Assert-Dlss5Runtime {
    if (-not (Test-Path -LiteralPath $dlss5Runtime -PathType Leaf)) {
        throw "DLSS5 runtime is missing. Download nvngx_dlssnr.dll, then run Install-DLSS5-Runtime.bat or place it at '$dlss5Runtime'. International: $dlss5RuntimeGoogleDrive ; China: $dlss5RuntimeBaidu (code: qisz)"
    }
    $actualHash = Get-Sha256 -Path $dlss5Runtime
    if (-not $actualHash.Equals($dlss5RuntimeSha256, [StringComparison]::OrdinalIgnoreCase)) {
        if ($RequireValidatedDlssNrHash) {
            throw "DLSS5 runtime hash mismatch. Expected $dlss5RuntimeSha256, got $actualHash."
        }
        Write-Host 'WARNING: nvngx_dlssnr.dll is not the release-validated RTX 50 runtime.' -ForegroundColor Yellow
        Write-Host "  Expected: $dlss5RuntimeSha256" -ForegroundColor Yellow
        Write-Host "  Selected: $actualHash" -ForegroundColor Yellow
        Write-Host '  Launch will continue with the player-supplied runtime. Compatibility is not guaranteed.' -ForegroundColor Yellow
    } else {
        Write-Host 'DLSS5 runtime: release-validated RTX 50 nvngx_dlssnr.dll detected.' -ForegroundColor Green
    }
}

function Test-PackageIntegrity {
    Assert-File -Path $manifestPath -Label 'Package integrity manifest'
    $entryCount = 0
    foreach ($line in (Get-Content -LiteralPath $manifestPath -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split('|', 2)
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "Invalid package manifest entry: $line"
        }
        $relativePath = $parts[0].Trim()
        if ($relativePath.Contains('..') -or [IO.Path]::IsPathRooted($relativePath)) {
            throw "Unsafe package manifest path: $relativePath"
        }
        $path = Join-Path $root $relativePath
        Assert-File -Path $path -Label "Manifest component '$relativePath'"
        $actualHash = Get-Sha256 -Path $path
        if (-not $actualHash.Equals($parts[1].Trim(), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Package integrity check failed for '$relativePath'. Expected $($parts[1].Trim()), got $actualHash. Re-extract the archive before continuing."
        }
        $entryCount++
    }
    if ($entryCount -lt 10) { throw 'Package integrity manifest contains too few protected components.' }
}

function Read-RequiredPath {
    param([string]$Prompt, [bool]$ExpectDirectory)
    while ($true) {
        # A Codex-launched PowerShell session has no interactive stdin. Avoid a
        # null .Trim() crash and make the missing invocation arguments explicit.
        $rawCandidate = Read-Host $Prompt
        if ($null -eq $rawCandidate) {
            throw "No interactive input is available for '$Prompt'. Supply the path as a launcher argument."
        }
        $candidate = $rawCandidate.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            Write-Host 'A path is required.' -ForegroundColor Yellow
            continue
        }
        if ($ExpectDirectory -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            return [IO.Path]::GetFullPath($candidate)
        }
        if (-not $ExpectDirectory -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
        Write-Host "Path does not exist: $candidate" -ForegroundColor Yellow
    }
}

function Get-GimiDirectory {
    param([string]$InputPath)
    $candidate = $InputPath.Trim().Trim('"')
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $candidate = Split-Path -Parent $candidate
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "The GIMI 3dmigoto directory does not exist: $InputPath"
    }
    $candidate = [IO.Path]::GetFullPath($candidate)
    Assert-File (Join-Path $candidate '3DMigoto Loader.exe') '3DMigoto Loader.exe'
    Assert-File (Join-Path $candidate 'd3dx.ini') 'GIMI d3dx.ini'
    return $candidate
}

function Set-IniValue {
    param([string]$Path, [string]$Section, [string]$Key, [string]$Value)
    # Construct the generic list explicitly. PowerShell 7 can otherwise bind
    # the array overload and return a fixed-size Object[] on some hosts.
    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
            [void]$lines.Add([string]$line)
        }
    }
    $sectionHeader = "[$Section]"
    $sectionIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim().Equals($sectionHeader, [StringComparison]::OrdinalIgnoreCase)) {
            $sectionIndex = $i
            break
        }
    }
    if ($sectionIndex -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) { $lines.Add('') }
        $lines.Add($sectionHeader)
        $lines.Add("$Key=$Value")
    } else {
        $keyPattern = '^\s*' + [regex]::Escape($Key) + '\s*='
        $found = $false
        for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim().StartsWith('[')) { break }
            if ($lines[$i] -match $keyPattern) {
                $lines[$i] = "$Key=$Value"
                $found = $true
                break
            }
        }
        if (-not $found) {
            $insertAt = $sectionIndex + 1
            while ($insertAt -lt $lines.Count -and -not $lines[$insertAt].Trim().StartsWith('[')) { $insertAt++ }
            $lines.Insert($insertAt, "$Key=$Value")
        }
    }
    [IO.File]::WriteAllLines($Path, [string[]]$lines, $utf8NoBom)
}

function Backup-FileIfExternal {
    param([string]$Path, [string]$Name, [hashtable]$State)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($text -match '(?m)^; Managed by GIMI DLSS Self-Contained Experiment$') { return }
    $backupPath = Join-Path $stateDirectory ("{0}.before-experiment.{1}.bak" -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    $State["${Name}Backup"] = $backupPath
}

function Configure-ReShade {
    param([hashtable]$State, [string]$Profile)
    $managedDirectory = Join-Path $stateDirectory 'reshade-runtime'
    $managedIni = Join-Path $managedDirectory 'ReShade.ini'
    $managedPreset = Join-Path $managedDirectory 'ReShadePreset.ini'
    $emptyAddonDirectory = Join-Path $reShadeDirectory 'empty-addons'
    $dlss5Profile = Test-Dlss5Profile -Profile $Profile
    $addonDirectory = if ($dlss5Profile) { $dlss5BridgeAddonDirectory } else { $emptyAddonDirectory }
    $shaderDirectory = Join-Path $reShadeDirectory 'reshade-shaders\Shaders'
    $textureDirectory = Join-Path $reShadeDirectory 'reshade-shaders\Textures'
    $cacheDirectory = Join-Path $reShadeDirectory 'cache'
    $screenshotDirectory = Join-Path $stateDirectory 'screenshots'
    New-Item -ItemType Directory -Force -Path $managedDirectory, $emptyAddonDirectory, $cacheDirectory, $screenshotDirectory | Out-Null
    $templateText = Get-Content -LiteralPath $reShadeIniTemplate -Raw -Encoding UTF8
    Write-Utf8File -Path $managedIni -Content ("; Managed by GIMI DLSS Self-Contained Experiment`r`n" + $templateText)
    Copy-Item -LiteralPath $reShadePreset -Destination $managedPreset -Force
    Set-IniValue -Path $managedIni -Section 'ADDON' -Key 'AddonPath' -Value $addonDirectory
    Set-IniValue -Path $managedIni -Section 'ADDON' -Key 'DisabledAddons' -Value ''
    Set-IniValue -Path $managedIni -Section 'GENERAL' -Key 'EffectSearchPaths' -Value $shaderDirectory
    Set-IniValue -Path $managedIni -Section 'GENERAL' -Key 'TextureSearchPaths' -Value $textureDirectory
    Set-IniValue -Path $managedIni -Section 'GENERAL' -Key 'PresetPath' -Value $managedPreset
    Set-IniValue -Path $managedIni -Section 'GENERAL' -Key 'IntermediateCachePath' -Value $cacheDirectory
    Set-IniValue -Path $managedIni -Section 'GENERAL' -Key 'NoReloadOnInit' -Value '0'
    Set-IniValue -Path $managedIni -Section 'INPUT' -Key 'KeyOverlay' -Value '36,0,0,0'
    Set-IniValue -Path $managedIni -Section 'SCREENSHOT' -Key 'SavePath' -Value $screenshotDirectory
    if ($dlss5Profile) {
        # ReShade loads the pre-NR observer from DllMain. It sees the private
        # D3D12 NGX call generated by OptiScaler, then uses nrchain_nvngx.dll to
        # submit signed Feature 18 before the original Feature 1 evaluation.
        # Graphics hooks remain disabled, so ReShade is an Add-on API host rather
        # than a competing D3D11/DXGI wrapper.
        # Mode 2 is the validated low-resolution 1:1 NR -> original DLSS SR path.
        # The add-on preserves the original SR call when Feature 18 fails.
        $loadFromDllMain = 'nr-before-sr.zh-CN.addon64'
        Set-IniValue -Path $managedIni -Section 'ADDON' -Key 'LoadFromDllMain' -Value $loadFromDllMain
        # Keep the observer enabled so it can register its NGX hooks.
        Set-IniValue -Path $managedIni -Section 'ADDON' -Key 'DisabledAddons' -Value ''
        # Keep a runtime config snapshot beside the pre-NR add-on for diagnostics.
        Copy-Item -LiteralPath $managedIni -Destination (Join-Path $dlss5BridgeAddonDirectory 'ReShade.ini') -Force
        $State['DLSS5AddonDirectory'] = $dlss5BridgeAddonDirectory
        $State['DLSS5BridgeAddon'] = $dlss5BridgeAddon
        $State['DLSS5NrChainBridge'] = $dlss5NrChainBridge
        $State['DLSS5Runtime'] = $dlss5Runtime
    }
    $State['ManagedReShadeIni'] = $managedIni
    $State['ManagedReShadePreset'] = $managedPreset
    $State['ManagedReShadeBasePath'] = $managedDirectory
}

function Configure-HostedReShadeSidecar {
    param([string]$GimiDirectory, [string]$Profile, [hashtable]$State)
    $sidecarPath = Join-Path $GimiDirectory 'GIMIHostedReShade.ini'
    $enabled = '1'
    $content = @(
        '[HostedReShade]'
        "Enabled=$enabled"
        "Dll=$reShadeDll"
        "Config=$($State['ManagedReShadeIni'])"
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($sidecarPath, $content, [Text.Encoding]::Unicode)
    $State['HostedReShadeSidecar'] = $sidecarPath
    $State['HostedReShadeEnabled'] = ($enabled -eq '1')
}

function Configure-OptiScaler {
    $optiIni = Join-Path $optiDirectory 'OptiScaler.ini'
    if (-not (Test-Path -LiteralPath $optiIni -PathType Leaf)) {
        Copy-Item -LiteralPath $optiTemplate -Destination $optiIni -Force
    }
    Set-IniValue -Path $optiIni -Section 'Upscalers' -Key 'Dx11Upscaler' -Value 'dlss_12'
    # Genshin exposes its temporal-upscaler inputs through the DX11 FSR2 ABI.
    # OptiScaler v0.2 defaults this switch to DX12, so pin all three input
    # selectors explicitly to keep the game contract on the correct API.
    Set-IniValue -Path $optiIni -Section 'Inputs' -Key 'EnableFsr2Inputs' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'Inputs' -Key 'UseFsr2Inputs' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'Inputs' -Key 'UseFsr2Dx11Inputs' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'FrameGen' -Key 'Enabled' -Value 'false'
    Set-IniValue -Path $optiIni -Section 'FrameGen' -Key 'FGInput' -Value 'nofg'
    Set-IniValue -Path $optiIni -Section 'FrameGen' -Key 'FGOutput' -Value 'nofg'
    Set-IniValue -Path $optiIni -Section 'Plugins' -Key 'LoadReShade' -Value 'false'
    Set-IniValue -Path $optiIni -Section 'Libraries' -Key 'OptiDllPath' -Value $optiDirectory
    Set-IniValue -Path $optiIni -Section 'Libraries' -Key 'NvngxDlssPath' -Value $nvngxDlssDll
    Set-IniValue -Path $optiIni -Section 'Libraries' -Key 'NvngxFeaturePath' -Value $optiDirectory
    Set-IniValue -Path $optiIni -Section 'DLSS' -Key 'Enabled' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'DLSS' -Key 'UseGenericAppIdWithDlss' -Value 'true'
    # The external Mode-2 add-on owns the only Neural Rendering pass. Keep
    # OptiScaler's built-in post-upscale pass off to prevent double NR.
    Set-IniValue -Path $optiIni -Section 'DlssNr' -Key 'Enabled' -Value 'false'
    Set-IniValue -Path $optiIni -Section 'Hooks' -Key 'SkipD3D11DeviceVTableHooks' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'Menu' -Key 'OverlayMenu' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'Menu' -Key 'ShortcutKey' -Value '0x2D'
    Set-IniValue -Path $optiIni -Section 'Log' -Key 'LogToFile' -Value 'true'
    Set-IniValue -Path $optiIni -Section 'Log' -Key 'LogLevel' -Value '1'
}

function Configure-BridgeRenderScale {
    param([string]$Profile, [hashtable]$State)

    # The release never changes Dx11FsrBridge's render-scale cache. It remains
    # controlled through the bridge UI and is not part of DLSS5 NR setup.
    $State['BridgeRenderScale'] = 'preserved'
}

function Configure-Gimi {
    param(
        [string]$GimiDirectory,
        [string]$GameExecutableName,
        [hashtable]$State
    )
    $gimiIni = Join-Path $GimiDirectory 'd3dx.ini'
    $lines = [string[]](Get-Content -LiteralPath $gimiIni -Encoding UTF8)
    $currentSection = ''
    $hookValue = $null
    $targetValue = $null
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[([^]]+)\]') {
            $currentSection = $Matches[1]
            continue
        }
        if ($currentSection.Equals('System', [StringComparison]::OrdinalIgnoreCase) -and
            $line -match '^\s*hook\s*=\s*(.*?)\s*$') {
            $hookValue = $Matches[1].Trim()
            continue
        }
        if ($currentSection.Equals('Loader', [StringComparison]::OrdinalIgnoreCase) -and
            $line -match '^\s*target\s*=\s*(.*?)\s*$') {
            $targetValue = $Matches[1].Trim().Trim('"')
        }
    }

    $hookNeedsUpdate = [string]::IsNullOrWhiteSpace($hookValue) -or
        -not $hookValue.Equals('recommended', [StringComparison]::OrdinalIgnoreCase)
    $targetNeedsUpdate = [string]::IsNullOrWhiteSpace($targetValue) -or
        -not $targetValue.Equals($GameExecutableName, [StringComparison]::OrdinalIgnoreCase)
    if ($hookNeedsUpdate -or $targetNeedsUpdate) {
        Backup-FileIfExternal -Path $gimiIni -Name 'd3dx.ini' -State $State
    }
    if ($hookNeedsUpdate) {
        Set-IniValue -Path $gimiIni -Section 'System' -Key 'hook' -Value 'recommended'
    }
    if ($targetNeedsUpdate) {
        Set-IniValue -Path $gimiIni -Section 'Loader' -Key 'target' -Value $GameExecutableName
    }
    $State['ManagedGimiIni'] = $gimiIni
    $State['GimiHookMode'] = 'recommended'
    $State['GimiTargetExecutable'] = $GameExecutableName

    $modsDirectory = Join-Path $GimiDirectory 'Mods'
    # An empty array in a PowerShell assignment is unrolled to $null. Keep an
    # explicit array so strict-mode Count access remains valid on clean GIMI
    # directories that do not contain a Mods folder yet.
    $modIniFiles = @()
    if (Test-Path -LiteralPath $modsDirectory -PathType Container) {
        $modIniFiles = @(Get-ChildItem -LiteralPath $modsDirectory -Filter '*.ini' -File -Recurse -ErrorAction SilentlyContinue)
    }
    $State['GimiModIniCount'] = $modIniFiles.Count
    $State['GimiModDirectory'] = $modsDirectory
}

function Configure-GimiHealthBarCompatibility {
    param([string]$GimiDirectory, [hashtable]$State)
    $healthBarPath = Join-Path $GimiDirectory 'Mods\BufferValues\HealthBar.ini'
    if (-not (Test-Path -LiteralPath $healthBarPath -PathType Leaf)) { return }

    $text = Get-Content -LiteralPath $healthBarPath -Raw -Encoding UTF8
    $unsupportedPattern = '(?m)^(\s*)store\s*=\s*\$health\s*,\s*ps-cb0\s*,\s*33\s*$'
    if ($text -notmatch $unsupportedPattern) { return }

    Backup-FileIfExternal -Path $healthBarPath -Name 'HealthBar.ini' -State $State
    $replacement = '$1; Disabled by the self-contained launcher: this GIMI build does not support store.'
    $updatedText = [regex]::Replace($text, $unsupportedPattern, $replacement)
    Write-Utf8File -Path $healthBarPath -Content $updatedText
    $State['HealthBarStoreDisabled'] = $true
}

function Install-GimiRuntime {
    param([string]$DestinationDirectory, [hashtable]$State)
    $destination = Join-Path $DestinationDirectory 'd3d11.dll'
    $sourceHash = Get-Sha256 -Path $gimiSourceDll
    $destinationHash = if (Test-Path -LiteralPath $destination -PathType Leaf) {
        Get-Sha256 -Path $destination
    } else { '' }
    if ($sourceHash -ne $destinationHash) {
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $backupPath = Join-Path $stateDirectory ("GIMI-d3d11.before-experiment.{0}.bak" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Copy-Item -LiteralPath $destination -Destination $backupPath -Force
            $State['GimiD3d11Backup'] = $backupPath
        }
        Copy-Item -LiteralPath $gimiSourceDll -Destination $destination -Force
    }
    $State['InstalledGimiD3d11'] = $destination
    $State['GimiD3d11Sha256'] = $sourceHash
}

function Write-UnlockerConfig {
    param([string]$ResolvedGamePath, [string]$GimiDll, [string]$Profile)
    $preloadDlls = @($GimiDll)
    $dllList = @($reShadeDll, $bridgeDll, $optiDll)
    $config = [ordered]@{
        GamePath = $ResolvedGamePath
        AutoStart = $true
        AutoClose = $true
        PopupWindow = $true
        Fullscreen = $false
        UseCustomRes = $false
        IsExclusiveFullscreen = $false
        StartMinimized = $true
        UsePowerSave = $false
        SuspendLoad = $false
        UseMobileUI = $false
        UseHDR = $true
        FPSTarget = 160
        CustomResX = 1920
        CustomResY = 1080
        MonitorNum = 1
        Priority = 3
        AdditionalCommandLine = ''
        LastVersionNotify = 0
        PreloadDlls = $preloadDlls
        GimiLoaderPath = ''
        DllList = $dllList
    }
    Write-Utf8File -Path (Join-Path $root 'fps_config.json') -Content ($config | ConvertTo-Json -Depth 4)
}

Assert-File $unlockerPath 'unlockfps_nc.exe'
Assert-File $gimiSourceDll 'Bundled GIMI d3d11.dll'
Assert-File $bridgeDll 'Dx11FsrBridge.dll'
Assert-File $optiDll 'OptiScaler.dll'
Assert-File $nvngxDlssDll 'nvngx_dlss.dll'
Assert-File $optiTemplate 'OptiScaler template'
Assert-File $reShadeDll 'ReShade64.dll'
Assert-File $reShadeIniTemplate 'ReShade template'
Assert-File $reShadePreset 'ReShade preset'
Assert-File $dlss5BridgeAddon 'DLSS5 DX11 bridge add-on'
Assert-File $dlss5NrChainBridge 'DLSS5 private NR chain bridge'
Assert-Dlss5Runtime
New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
Test-PackageIntegrity

$saved = $null
if (-not $ForceConfigure -and (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    try { $saved = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $saved = $null }
}

if ([string]::IsNullOrWhiteSpace($GamePath)) {
    if ($null -ne $saved -and (Test-Path -LiteralPath $saved.GamePath -PathType Leaf)) { $GamePath = $saved.GamePath }
    else { $GamePath = Read-RequiredPath -Prompt 'Enter the full path to YuanShen.exe or GenshinImpact.exe' -ExpectDirectory $false }
}
if ([string]::IsNullOrWhiteSpace($GimiPath)) {
    if ($null -ne $saved -and (Test-Path -LiteralPath $saved.GimiPath -PathType Container)) { $GimiPath = $saved.GimiPath }
    else { $GimiPath = Read-RequiredPath -Prompt 'Enter the full path to the GIMI 3dmigoto directory' -ExpectDirectory $true }
}

$GamePath = [IO.Path]::GetFullPath($GamePath.Trim().Trim('"'))
Assert-File $GamePath 'Genshin Impact game executable'
$gameExecutableName = [IO.Path]::GetFileName($GamePath)
if ($gameExecutableName -notin @('YuanShen.exe', 'GenshinImpact.exe')) {
    throw "The selected game executable must be YuanShen.exe or GenshinImpact.exe: $GamePath"
}
$GimiPath = Get-GimiDirectory -InputPath $GimiPath

$runningGame = @(Get-Process -Name 'GenshinImpact', 'YuanShen' -ErrorAction SilentlyContinue)
if ($runningGame.Count -gt 0) {
    throw 'Close Genshin Impact before configuring or launching this package.'
}

$state = @{
    PackageRoot = $root
    GamePath = $GamePath
    GimiPath = $GimiPath
    ConfiguredAt = (Get-Date).ToString('s')
    InjectionOrder = @('GIMI d3d11 preload', 'ReShade64.dll', 'Dx11FsrBridge.dll', 'OptiScaler.dll')
}
$state['InjectionOrder'] = @(
    'GIMI d3d11 preload',
    'ReShade64.dll passive Add-on host (graphics hooks disabled)',
    'NR-before-SR add-on registered from ReShade DllMain',
    'Dx11FsrBridge.dll',
    'Patched OptiScaler v0.2.0 DLSS-on-DX12 bridge',
    'Low-resolution 1:1 DLSS5 NR followed by original DLSS Super Resolution',
    'GIMI-hosted ReShade runtime on final Present'
)
Install-GimiRuntime -DestinationDirectory $GimiPath -State $state
Configure-Gimi -GimiDirectory $GimiPath -GameExecutableName $gameExecutableName -State $state
Configure-GimiHealthBarCompatibility -GimiDirectory $GimiPath -State $state
Configure-OptiScaler
Configure-BridgeRenderScale -Profile $TestProfile -State $state
Configure-ReShade -State $state -Profile $TestProfile
Configure-HostedReShadeSidecar -GimiDirectory $GimiPath -Profile $TestProfile -State $state
Write-UnlockerConfig -ResolvedGamePath $GamePath -GimiDll $state['InstalledGimiD3d11'] -Profile $TestProfile
Write-Utf8File -Path $statePath -Content ($state | ConvertTo-Json -Depth 4)

Write-Status 'Configuration completed.' Green
Write-Host "  Game: $GamePath"
Write-Host "  GIMI: $GimiPath"
Write-Host "  GIMI target: $gameExecutableName"
Write-Host '  GIMI hook: recommended (required for the UnlockFPS proxy device)'
if ([int]$state['GimiModIniCount'] -gt 0) {
    Write-Host "  GIMI mods: $($state['GimiModIniCount']) INI file(s) under $($state['GimiModDirectory'])"
} else {
    Write-Host '  GIMI mods: no .ini files found under the selected Mods directory' -ForegroundColor Yellow
}
if ($state.ContainsKey('HealthBarStoreDisabled')) {
    Write-Host '  HealthBar compatibility: unsupported store directive disabled (original backed up in state)' -ForegroundColor Yellow
}
Write-Host '  Mode: render-resolution DLSS5 NR -> original DLSS Super Resolution'
Write-Host '  DLL order: GIMI preload -> passive ReShade Add-on host -> NR-before-SR -> Dx11FsrBridge -> DLSS-on-DX12 -> GIMI final Present'
Write-Host '  ReShade: hosted by GIMI after the final upscaled frame; press Home in-game to open its overlay.'
Write-Host '  DLSS5: Mode 2 runs Feature 18 at render resolution before DLSS Feature 1.'
Write-Host '  Control profile: OptiScaler built-in post-NR is disabled; original DLSS owns final spatial upscaling.' -ForegroundColor Yellow

if ($ConfigureOnly) { exit 0 }

$existingUnlocker = Get-Process -Name 'unlockfps_nc' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $unlockerPath }
if ($null -ne $existingUnlocker) {
    throw 'An existing UnlockFPS instance from this package is still running. Close it before launching again.'
}

Write-Status 'Launching Genshin Impact through the bundled UnlockFPS runtime...' Green
$launchStartedAt = Get-Date
# These variables are inherited by UnlockFPS and then Genshin. They tell the
# bundled GIMI runtime to create a ReShade C-API runtime, while graphics hooks
# stay disabled so ReShade cannot wrap the game's swap chain.
$env:GIMI_HOSTED_RESHADE_DLL = $reShadeDll
$env:GIMI_HOSTED_RESHADE_CONFIG = $state['ManagedReShadeIni']
$env:RESHADE_DISABLE_GRAPHICS_HOOK = '1'
$env:RESHADE_BASE_PATH_OVERRIDE = $state['ManagedReShadeBasePath']
# The hosted runtime needs ReShade's normal window input path for Home.
Remove-Item Env:RESHADE_DISABLE_INPUT_HOOK -ErrorAction SilentlyContinue
$launcher = Start-Process -FilePath $unlockerPath -WorkingDirectory $root -PassThru
$gameObserved = $false
for ($attempt = 0; $attempt -lt 8; $attempt++) {
    Start-Sleep -Seconds 1
    $gameObserved = $null -ne (Get-Process -Name 'GenshinImpact', 'YuanShen' -ErrorAction SilentlyContinue |
        Where-Object { $_.StartTime -ge $launchStartedAt })
    if ($gameObserved) { break }
}
if (-not $gameObserved -and $launcher.HasExited) {
    throw 'The launcher exited before a game process was observed. Check the logs in components\\Bridge, components\\OptiScaler, and the game directory.'
}
if ($gameObserved) {
    Write-Status 'Game process observed. The UnlockFPS window may close after the game process takes over.' Green
} else {
    Write-Status 'UnlockFPS is still starting the game. Check the game process or logs if it does not appear.' Yellow
}
