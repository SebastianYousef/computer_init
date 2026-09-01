@echo off
REM ===========================================================================
REM  github_windows.bat - double-click launcher for github_windows.ps1
REM  Runs the PowerShell script without changing your execution policy.
REM ===========================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0github_windows.ps1"
echo.
pause
