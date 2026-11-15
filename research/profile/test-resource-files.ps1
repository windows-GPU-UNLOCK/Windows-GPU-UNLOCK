# Combined existing-file observations; never stage, generate a profile or access hardware.
[CmdletBinding()]
param([string]$CaptureFolder,[string]$Clang='clang',[string]$VcVars,[string]$Python='python',[string]$OutputRoot,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$chosenFolder=$CaptureFolder;$chosenClang=$Clang;$chosenVcVars=$VcVars;$chosenSelfTest=[bool]$SelfTest
. (Join-Path $PSScriptRoot 'test-prom-cache.ps1')
. (Join-Path $PSScriptRoot 'collection-host.ps1')
$CaptureFolder=$chosenFolder;$Clang=$chosenClang;$VcVars=$chosenVcVars;$SelfTest=$chosenSelfTest
$pythonApplication=Resolve-GuPythonApplication $Python
Import-GuHostCompiler $VcVars
$locator=Build-GuFwsecLocate $repo $Clang
function Read-ResourceFiles([string]$Folder){
 $prom=Test-PromCache $Folder $locator
 $lines=& $pythonApplication -I -B (Join-Path $PSScriptRoot 'review-driver-capture.py') $Folder
 if($LASTEXITCODE -ne 0){throw 'Existing-file driver review failed.'}
 $driver=($lines -join [Environment]::NewLine)|ConvertFrom-Json
 if($driver.test -cne 'captured-driver-review-v1' -or $driver.hardware_verified -or $driver.write_eligible -or $driver.profile_generated){throw 'Unexpected driver scope.'}
 return [ordered]@{Test='resource-files-review-v1';Prom=$prom;Drivers=$driver;
  HardwareVerified=$false;OwnershipVerified=$false;SignatureTrustVerified=$false;WriteEligible=$false;ProfileGenerated=$false}
}
if($SelfTest){
 $folder=Join-Path ([IO.Path]::GetTempPath()) ('resource-files-'+[guid]::NewGuid().ToString('N'))
 New-Item -ItemType Directory -Path $folder|Out-Null
 [IO.File]::WriteAllBytes((Join-Path $folder 'PROM.BIN'),(New-Object byte[] 1MB))
 $r=Read-ResourceFiles $folder
 if($r.Prom.FwsecState -cne 'not-found' -or $r.Drivers.status -cne 'unavailable' -or $r.WriteEligible -or ($r|ConvertTo-Json -Depth 12).Contains($folder)){throw 'Combined scope/refusal/privacy regression.'}
 Write-Host 'PASS: combined production PROM refusal, missing-driver report, input preservation and privacy; no hardware.';exit
}
if(!$CaptureFolder){$CaptureFolder=Read-Host 'Existing successful resource capture folder containing PROM.BIN, DIAG and IMG files'}
$result=Read-ResourceFiles $CaptureFolder
$out=New-GuCollectionOutput $OutputRoot 'GPU-Unlock-Resource-Files' $CaptureFolder
$path=Join-Path $out 'resource-files.json'
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+'. Preserve original files; no profile generation, staging, settings changes or boot.')
