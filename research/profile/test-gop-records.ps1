# Trusted CPU-only diagnostic-record regressions. No EFI build, calls or hardware.
[CmdletBinding()]
param([string]$Python='python')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'collection-host.ps1')
$command=Resolve-GuPythonApplication $Python
& $command -I -B (Join-Path $PSScriptRoot 'test_gop_records.py')
if($LASTEXITCODE -ne 0){throw 'GOP record regression failed. Stop; no hardware or settings change.'}
Write-Host 'PASS: reported GOP metadata is distinct from absent GOP; no SetMode/reconnect authorization. Return only this PASS or short sanitized failure; no new captures.'
