# Native RAM-only test of trusted production path parsing. No EFI build or execution.
[CmdletBinding()]
param([string]$Clang='clang',[string]$Python='python',[string]$VcVars)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'host.ps1')
. (Join-Path $PSScriptRoot 'collection-host.ps1')
$command=Resolve-GuPythonApplication $Python
Import-GuHostCompiler $VcVars
& $command -I -B (Join-Path $PSScriptRoot 'test-media-contract.py') --clang $Clang
if($LASTEXITCODE -ne 0){throw 'Offline media contract test failed. Stop without installing, changing settings or booting anything.'}
