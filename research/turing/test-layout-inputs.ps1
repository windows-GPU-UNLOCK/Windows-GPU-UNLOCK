# Compile trusted CPU-only research model, no captured files or GPU operations.
[CmdletBinding()]
param([string]$Clang='clang',[string]$VcVars)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../profile/host.ps1')
Import-GuHostCompiler $VcVars
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents unavailable.'}
$out=Join-Path $docs ('GPU-Unlock-Turing-Layout-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $out|Out-Null
$exe=Join-Path $out 'layout-host.exe'
$layout=Join-Path $PSScriptRoot '../../internal-boot/unlock/vendor/layout_610.c'
& $Clang -std=c11 -O1 -Wall -Wextra -Werror (Join-Path $PSScriptRoot 'test-layout-inputs.c') $layout -o $exe
if($LASTEXITCODE -ne 0){throw 'Host build failed. Stop; no installation, hardware or settings change.'}
& $exe
if($LASTEXITCODE -ne 0){throw 'Research model failed; no hardware retry.'}
$metadata=Join-Path $out 'v2-metadata-host.exe'
& $Clang -std=c11 -O1 -Wall -Wextra -Werror (Join-Path $PSScriptRoot 'test-fwsec-v2-metadata.c') -o $metadata
if($LASTEXITCODE -ne 0){throw 'Research metadata compile failed; no hardware retry.'}
& $metadata
if($LASTEXITCODE -ne 0){throw 'Research metadata failed; no hardware retry.'}
$r=[ordered]@{Test='turing-layout-input-model-v2';Passed=$true;SyntheticRangeCombinations=2016;MetadataRefusalCases=79;ActualExistingLayoutCalculator=$true;CapturedHardwareEvidence=$false;HardwareAccess=$false;EfiExecuted=$false;ProfileAdmitted=$false;WriteEligible=$false}
$path=Join-Path $out 'turing-layout.json';$r|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only '+$path+'. Synthetic arithmetic only; no EFI, registers or profile admission.')
