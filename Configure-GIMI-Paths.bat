@echo off
setlocal
chcp 65001>nul
set "ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%ROOT%Configure-GIMI-Paths.ps1" -Force
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" if not "%CODE%"=="2" pause
exit /b %CODE%
