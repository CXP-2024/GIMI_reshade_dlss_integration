@echo off
setlocal
chcp 65001>nul
set "ROOT=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%ROOT%Configure-And-Launch.ps1" -ConfigureOnly -ForceConfigure -TestProfile PreNRThenDLSS
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" pause
exit /b %CODE%
