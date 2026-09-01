@echo off
REM ===========================================================================
REM  vscode_windows.bat - double-click launcher for vscode_windows.ps1
REM  Runs the PowerShell script without changing your execution policy.
REM ===========================================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vscode_windows.ps1"
echo.
pause
