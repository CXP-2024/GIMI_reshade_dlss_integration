@echo off
setlocal
title Verify GIMI + DLSS + DLSS5 dual-mode package
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Verify-Installation.ps1" -LastRun %*
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" pause
exit /b %exitCode%
