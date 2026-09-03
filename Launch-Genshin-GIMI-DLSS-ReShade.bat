@echo off
setlocal
title GIMI + DLSS + Hosted ReShade
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-And-Launch.ps1" -TestProfile GimiBridgeHostedReShade
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" pause
exit /b %exitCode%
