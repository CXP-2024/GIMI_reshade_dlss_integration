@echo off
setlocal
rem Backward-compatible entry point. The hosted ReShade launcher is now canonical.
call "%~dp0Launch-Genshin-GIMI-DLSS-ReShade.bat"
exit /b %ERRORLEVEL%
