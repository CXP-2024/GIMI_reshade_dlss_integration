[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
$launcher = Join-Path $PSScriptRoot 'Configure-And-Launch.ps1'
& $launcher -ConfigureOnly -ForceConfigure:$Force -TestProfile PreNRThenDLSS
exit $LASTEXITCODE
