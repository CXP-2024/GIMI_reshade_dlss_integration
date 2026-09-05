[CmdletBinding()]
param(
    [switch]$Force,
    [ValidateSet('auto', 'rtx30', 'rtx40', 'rtx50')]
    [string]$NrProfile = 'auto'
)

$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot 'Configure-And-Launch.ps1'
& $launcher -ConfigureOnly -ForceConfigure:$Force -TestProfile PreNRThenDLSS -NrProfile $NrProfile
exit $LASTEXITCODE
