@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-DLSS5-Runtime.ps1" %*
if errorlevel 1 (
  echo.
  echo DLSS5 runtime installation failed.
  pause
  exit /b 1
)
echo.
pause
