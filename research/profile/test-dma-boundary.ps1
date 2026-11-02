# Compile/run the trusted production port's existing RAM-only mock suite.
[CmdletBinding()]
param([string]$Clang='clang',[string]$VcVars,[string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'host.ps1')
Import-GuHostCompiler $VcVars
if(!$OutputRoot){$OutputRoot=[Environment]::GetFolderPath('MyDocuments')}
$parent=Get-Item -LiteralPath $OutputRoot
if(!$parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $parent.FullName.StartsWith('\\')){throw 'Use an existing regular local output directory.'}
$out=Join-Path $parent.FullName ('GPU-Unlock-Dma-Boundary-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $out|Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$port=Join-Path $repo 'internal-boot/unlock'
$exe=Join-Path $out 'port-host.exe'
& $Clang -std=c11 -O1 -Wall -Wextra -Werror -Wno-unused-parameter -D_CRT_SECURE_NO_WARNINGS -DGU_HOST_WRITE_TEST ('-I'+(Join-Path $repo 'deps/edk2/MdePkg/Include')) ('-I'+(Join-Path $repo 'deps/edk2/MdePkg/Include/X64')) (Join-Path $port 'tests/test_port.c') (Join-Path $port 'port.c') -o $exe
if($LASTEXITCODE -ne 0){throw 'Host compile failed. Stop without installing/changing settings or booting hardware.'}
& $exe
if($LASTEXITCODE -ne 0){throw 'Host port regression failed. No hardware repeat.'}
$r=[ordered]@{Test='dma32-rounded-boundary-v2';ActualProductionPortMocked=$true;Exact32BitEndAccepted=$true;RoundedCrossingRefused=$true;InvalidMapCleanupFailureCases=6;RetainedMappingRetryRefused=$true;HardwareAccess=$false;EfiExecuted=$false;WriteEligible=$false}
$path=Join-Path $out 'dma-boundary.json'
$r|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('PASS: actual GuDmaAllocate boundary/unwind mocks; return only reviewed '+$path+'. No physical experiment requested.')
