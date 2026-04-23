@echo off
:: ============================================================
::  Workstation As Code — Batch Launcher
::  Launches setup.ps1 with elevated privileges (Run as Admin)
:: ============================================================

:: Check if running as Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [!] This script requires Administrator privileges.
    echo  [*] Requesting elevation...
    echo.
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  ======================================================
echo   Workstation As Code — Automated Environment Setup
echo  ======================================================
echo.
echo  [*] Starting provisioning...
echo.

:: Run the PowerShell setup script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

echo.
echo  [*] Script finished. Check the logs/ folder for details.
echo.
pause
