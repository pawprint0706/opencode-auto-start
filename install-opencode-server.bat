@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-opencode-server.ps1"
set "exitCode=%ERRORLEVEL%"

echo.
pause
exit /b %exitCode%
