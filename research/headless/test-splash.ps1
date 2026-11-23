# SPDX-License-Identifier: GPL-2.0-only
# CPU-only tests of the production player with simulated UEFI services.
param([string]$Clang='clang', [string]$Python='python', [string]$VcVars)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../profile/host.ps1')
Import-GuHostCompiler $VcVars
& $Python (Join-Path $PSScriptRoot 'test-splash.py') --clang $Clang
if ($LASTEXITCODE) { throw 'Boot splash tests failed' }
