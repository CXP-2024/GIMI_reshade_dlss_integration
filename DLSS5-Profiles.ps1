Set-StrictMode -Version Latest

$script:Dlss5ProfileDefinitions = @{
    rtx30 = [ordered]@{
        Name = 'rtx30'
        AssetProfile = 'rtx30'
        DirectoryName = 'pre-nr-rtx30'
        DisplayName = 'RTX 30 Stable'
        SupportLevel = 'validated'
        RuntimeSha256 = '6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927'
        NrChainSha256 = '46041A5FF91AE2FD907E310D132AABC3C4A1ECD48DACE511B8672909D5D9C2FB'
    }
    rtx40 = [ordered]@{
        Name = 'rtx40'
        AssetProfile = 'rtx30'
        DirectoryName = 'pre-nr-rtx30'
        DisplayName = 'RTX 40 via RTX 30 compatibility backend'
        SupportLevel = 'experimental'
        RuntimeSha256 = '6EB209E764F39872625DEBD6ABAF45E2BB6322F6F270F781F70C059AE30B3927'
        NrChainSha256 = '46041A5FF91AE2FD907E310D132AABC3C4A1ECD48DACE511B8672909D5D9C2FB'
    }
    rtx50 = [ordered]@{
        Name = 'rtx50'
        AssetProfile = 'rtx50'
        DirectoryName = 'pre-nr'
        DisplayName = 'RTX 50 Stable'
        SupportLevel = 'validated'
        RuntimeSha256 = 'E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E'
        NrChainSha256 = 'DB26E486592B252072BA5734FC2B27412863B8526826225640C837D4B4D11B60'
    }
}

function Get-Dlss5ProfileDefinition {
    param([Parameter(Mandatory = $true)][string]$Name)

    $normalized = $Name.Trim().ToLowerInvariant()
    if (-not $script:Dlss5ProfileDefinitions.ContainsKey($normalized)) {
        throw "Unknown DLSS5 NR profile: $Name"
    }
    return $script:Dlss5ProfileDefinitions[$normalized]
}

function Get-NvidiaGpuNames {
    $names = @()
    try {
        $names = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -match '(?i)NVIDIA|GeForce|RTX' } |
            ForEach-Object { [string]$_.Name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
        try {
            $names = @(Get-WmiObject -Class Win32_VideoController -ErrorAction Stop |
                Where-Object { $_.Name -match '(?i)NVIDIA|GeForce|RTX' } |
                ForEach-Object { [string]$_.Name } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        } catch { }
    }
    return @($names | Select-Object -Unique)
}

function Resolve-Dlss5NrProfile {
    param(
        [ValidateSet('auto', 'rtx30', 'rtx40', 'rtx50')]
        [string]$RequestedProfile = 'auto',
        [string]$SavedProfile = ''
    )

    if ($RequestedProfile -ne 'auto') {
        return $RequestedProfile
    }

    $gpuNames = @(Get-NvidiaGpuNames)
    foreach ($name in $gpuNames) {
        if ($name -match '(?i)\bRTX\s*50\d{2}\b') {
            Write-Host "Detected GPU: $name" -ForegroundColor Green
            return 'rtx50'
        }
    }
    foreach ($name in $gpuNames) {
        if ($name -match '(?i)\bRTX\s*40\d{2}\b') {
            Write-Host "Detected GPU: $name" -ForegroundColor Yellow
            Write-Host 'RTX 40 will use the complete RTX 30 compatibility backend and runtime profile.' -ForegroundColor Yellow
            Write-Host 'This is an experimental path: NR may be unstable or inactive, but launch is not blocked.' -ForegroundColor Yellow
            return 'rtx40'
        }
    }
    foreach ($name in $gpuNames) {
        if ($name -match '(?i)\bRTX\s*30\d{2}\b') {
            Write-Host "Detected GPU: $name" -ForegroundColor Green
            return 'rtx30'
        }
    }

    if ($SavedProfile -in @('rtx30', 'rtx40', 'rtx50')) {
        Write-Host "Could not classify the current GPU; reusing saved profile '$SavedProfile'." -ForegroundColor Yellow
        return $SavedProfile
    }

    if ($gpuNames.Count -gt 0) {
        Write-Host ("No dedicated profile exists for: {0}" -f ($gpuNames -join ', ')) -ForegroundColor Yellow
    } else {
        Write-Host 'Could not identify an NVIDIA GPU automatically.' -ForegroundColor Yellow
    }
    Write-Host 'Falling back to the RTX 30 compatibility profile. Override with -NrProfile rtx30|rtx40|rtx50.' -ForegroundColor Yellow
    return 'rtx30'
}
