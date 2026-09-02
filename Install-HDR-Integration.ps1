[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$GimiPath
)

$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSCommandPath))
$stagedDll = Join-Path $packageRoot 'GIMI\d3d11.dll'
$GimiPath = [IO.Path]::GetFullPath($GimiPath.Trim().Trim('"'))
$targetDll = Join-Path $GimiPath 'd3d11.dll'

function Get-Sha256([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))).Replace('-', '')
    }
    finally { $sha.Dispose() }
}

foreach ($path in @($stagedDll, (Join-Path $GimiPath 'd3dx.ini'), (Join-Path $GimiPath 'Mods'))) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path was not found: $path"
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (Test-Path -LiteralPath $targetDll) {
    $backup = Join-Path $GimiPath "d3d11.dll.before-integration-$stamp"
    if ($PSCmdlet.ShouldProcess($targetDll, "Back up to $backup")) {
        Copy-Item -LiteralPath $targetDll -Destination $backup -Force
        Write-Host "Backed up existing GIMI DLL to $backup"
    }
}

if ($PSCmdlet.ShouldProcess($targetDll, 'Install patched HDR-compatible GIMI DLL')) {
    Copy-Item -LiteralPath $stagedDll -Destination $targetDll -Force
}

$hash = Get-Sha256 $targetDll
Write-Host "Installed GIMI DLL SHA256: $hash"
Write-Host "The DLL is ready. Run Launch-Genshin-GIMI-UnlockFPS.bat from this repository."
