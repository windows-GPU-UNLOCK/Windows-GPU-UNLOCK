@echo off
setlocal
title Windows GPU diagnostics
powershell.exe -NoLogo -NoProfile -File "%~dp0tools\start-capture.ps1" %*
set "gu_result=%errorlevel%"
if not "%gu_result%"=="0" echo Diagnostics stopped. Read the message above or docs\CAPTURE-SETUP.en.md.
if "%~1"=="" pause
exit /b %gu_result%
