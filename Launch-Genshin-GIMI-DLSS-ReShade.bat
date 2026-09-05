@echo off
setlocal
title GIMI + ReShade + DLSS + DLSS5 Dual Mode
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Configure-And-Launch.ps1" -TestProfile PreNRThenDLSS %*
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" pause
exit /b %exitCode%
