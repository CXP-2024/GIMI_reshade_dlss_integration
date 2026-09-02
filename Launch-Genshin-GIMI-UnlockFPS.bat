@echo off
setlocal
chcp 65001>nul
set "ROOT=%~dp0"

if not exist "%ROOT%unlockfps_nc.exe" (
  echo unlockfps_nc.exe not found in "%ROOT%"
  pause
  exit /b 1
)

rem First run (or invalid saved paths) opens the two-step path wizard.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%ROOT%Configure-GIMI-Paths.ps1"
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo Configuration was cancelled or failed. Exit code: %CODE%
  pause
  exit /b %CODE%
)

start "Genshin GIMI + UnlockFPS" "%ROOT%unlockfps_nc.exe"
endlocal
