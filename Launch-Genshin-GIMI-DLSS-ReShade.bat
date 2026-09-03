@echo off
setlocal
title GIMI + DLSS + DLSS5 Native NR + Hosted ReShade
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-And-Launch.ps1" -TestProfile StableNativeNR
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" pause
exit /b %exitCode%
