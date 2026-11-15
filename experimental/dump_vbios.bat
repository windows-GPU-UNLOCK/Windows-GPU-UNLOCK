@echo off
setlocal EnableDelayedExpansion
:: Self-elevate to Administrator if not already running as admin
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [i] Requesting Administrator privileges to access GPU VBIOS...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:: If smart PowerShell dumper with strict hardware ID matching is present, execute it
if exist "%~dp0dump_vbios.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dump_vbios.ps1"
    goto :done
)

:: Pure batch fallback with multi-GPU index scanning
echo ========================================================
echo   UNIVERSAL VBIOS DUMP (Multi-GPU nvflashk Fallback)
echo ========================================================

set "NVFLASH=%~dp0tools\nvflashk.exe"
if not exist "!NVFLASH!" set "NVFLASH=%~dp0nvflashk.exe"
if not exist "!NVFLASH!" set "NVFLASH=%~dp0..\nvflashk.exe"

if not exist "!NVFLASH!" (
    echo [ERROR] nvflashk.exe not found!
    echo Please ensure nvflashk.exe is in the same folder.
    goto :done
)

if not exist "%~dp0EFI\VBIOS" mkdir "%~dp0EFI\VBIOS"

for %%I in (0 1 2 3) do (
    echo [i] Attempting VBIOS dump from adapter index %%I...
    set "TMPROM=%TEMP%\nvflash_%RANDOM%_%%I.rom"
    if exist "!TMPROM!" del /f /q "!TMPROM!" >nul 2>&1
    "!NVFLASH!" --index=%%I --save "!TMPROM!" >nul 2>&1
    if not exist "!TMPROM!" (
        "!NVFLASH!" --index=%%I -b "!TMPROM!" >nul 2>&1
    )
    if exist "!TMPROM!" (
        for %%F in ("!TMPROM!") do if %%~zF GTR 0 (
            move /y "!TMPROM!" "%~dp0EFI\VBIOS\gpu_adapter_%%I.rom" >nul 2>&1
            echo [SUCCESS] Adapter %%I saved to EFI\VBIOS\gpu_adapter_%%I.rom
        )
        if exist "!TMPROM!" del /f /q "!TMPROM!" >nul 2>&1
    )
)

:done
echo.
echo Press any key to exit...
pause >nul
