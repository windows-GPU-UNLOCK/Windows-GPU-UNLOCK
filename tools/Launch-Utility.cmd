@echo off
setlocal
title Windows GPU UNLOCK - Utility Launcher

:: Check for administrative rights
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunAdmin
) else (
    goto :PromptElevation
)

:PromptElevation
echo ============================================================
echo   Windows GPU UNLOCK - Launcher
echo ============================================================
echo.
echo Standard User permissions detected.
echo Administrative privileges are recommended for UEFI/BCD operations.
echo.
echo [1] Launch with Administrator Elevation (Recommended)
echo [2] Launch in User Mode (Read-only diagnostics)
echo.
set /p choice="Select an option (default: 1): "
if "%choice%"=="" set choice=1

if "%choice%"=="1" (
    echo Requesting Administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0gpu_unlock_utility\GpuUnlockUtility.ps1\"\"' -Verb RunAs"
    exit /b
)


:RunAdmin
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0gpu_unlock_utility\GpuUnlockUtility.ps1" %*
if %errorlevel% neq 0 (
    echo.
    echo Utility exited with code %errorlevel%.
    pause
)

