# One read-only firmware-menu inspection plan; never changes policy or boots EFI.
[CmdletBinding()]
param([ValidateSet('issue135')][string]$Machine='issue135',[switch]$Verify,[string]$Folder,[switch]$SelfTest)
$ErrorActionPreference='Stop'
function New-InspectionReport($Comparison,[string]$ReturnedWithoutSave,[string]$MenuMatched,[string]$OsType){
 $allowed=@('YES','NO','UNKNOWN')
 if($ReturnedWithoutSave -cnotin $allowed -or $MenuMatched -cnotin $allowed -or $OsType -cnotin $allowed){throw 'Use YES, NO or UNKNOWN only.'}
 $match=$Comparison.Status -ceq 'observations-match' -and $Comparison.ExactConfigurationUnchanged -is [bool] -and $Comparison.ExactConfigurationUnchanged -and $Comparison.PublicVariablesUnchanged -is [bool] -and $Comparison.PublicVariablesUnchanged -and $Comparison.EnabledDecryptedWindowsPathObserved -is [bool] -and $Comparison.EnabledDecryptedWindowsPathObserved
 return [ordered]@{Test='firmware-menu-inspection-v1';BaselineObservationsMatch=[bool]$match;OwnerReportedNoSave=$ReturnedWithoutSave;OwnerReportedMenuMatch=$MenuMatched;OwnerReportedWindowsUefiOsType=$OsType;RawPolicyFingerprintsExported=$false;PolicyChangeAuthorized=$false;EfiExecutionAuthorized=$false;RecoveryVerified=$false;FirmwareTrustEstablished=$false;HardwareUnlockTested=$false;WriteEligible=$false}
}
function Read-InspectionReceipt([string]$Root){
 $p=Join-Path $Root 'inspection-receipt.json';$f=Get-Item -LiteralPath $p
 if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 64KB){throw 'Invalid inspection receipt.'}
 $r=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
 if($r.Format -ne 1 -or $r.Machine -cne 'issue135' -or $r.Scope -cne 'firmware-menu-inspection-no-save' -or $r.BaselineSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'Invalid inspection scope.'}
 $baseline=Join-Path $Root 'baseline.json';$f=Get-Item -LiteralPath $baseline
 if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 64KB){throw 'Invalid baseline file.'}
 if((Get-FileHash -LiteralPath $baseline -Algorithm SHA256).Hash.ToLowerInvariant() -cne $r.BaselineSha256){throw 'Local baseline changed. Stop; do not repair or proceed.'}
 return $baseline
}
if($SelfTest){
 $comparison=[pscustomobject]@{Status='observations-match';ExactConfigurationUnchanged=$true;PublicVariablesUnchanged=$true;EnabledDecryptedWindowsPathObserved=$true}
 $r=New-InspectionReport $comparison 'YES' 'YES' 'YES'
 if(!$r.BaselineObservationsMatch -or $r.PolicyChangeAuthorized -or $r.EfiExecutionAuthorized -or $r.RecoveryVerified){throw 'Scope widened.'}
 $comparison.PublicVariablesUnchanged=$false
 if((New-InspectionReport $comparison 'UNKNOWN' 'UNKNOWN' 'UNKNOWN').BaselineObservationsMatch){throw 'Changed policy accepted.'}
 $refused=$false;try{New-InspectionReport $comparison 'PRIVATE' 'YES' 'YES'}catch{$refused=$true};if(!$refused){throw 'Unbounded owner text accepted.'}
 $dir=Join-Path ([IO.Path]::GetTempPath()) ('policy-inspection-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
 $baseline=Join-Path $dir 'baseline.json';'{"fixture":true}'|Set-Content -LiteralPath $baseline -Encoding utf8
 [ordered]@{Format=1;Machine='issue135';Scope='firmware-menu-inspection-no-save';BaselineSha256=(Get-FileHash $baseline -Algorithm SHA256).Hash.ToLowerInvariant()}|ConvertTo-Json|Set-Content (Join-Path $dir 'inspection-receipt.json') -Encoding utf8
 if((Read-InspectionReceipt $dir) -cne $baseline){throw 'Baseline receipt roundtrip failed.'}
 'altered'|Set-Content -LiteralPath $baseline
 $refused=$false;try{Read-InspectionReceipt $dir}catch{$refused=$true};if(!$refused){throw 'Changed baseline accepted.'}
 Write-Host 'PASS: no-save inspection scope, unknown/changed observations, bounded owner answers and baseline receipt/tamper checks. No system queries.';exit
}
try{
 if($Verify){
  if(!$Folder){$Folder=Read-Host 'Original Documents policy-baseline folder (keep it local)'}
  $baseline=Read-InspectionReceipt $Folder
  $result=& (Join-Path $PSScriptRoot 'test-policy-baseline.ps1') -Mode Verify -Baseline $baseline -PassThru
  if(!$? -or !$result -or !$result.ReportPath){throw 'Read-only comparison unavailable.'}
  $comparison=Get-Content -LiteralPath $result.ReportPath -Raw|ConvertFrom-Json
  $noSave=Read-Host 'Did Windows return without saving firmware changes? YES, NO or UNKNOWN'
  $menu=Read-Host 'Did Boot / Secure Boot / OS Type labels match? YES, NO or UNKNOWN'
  $os=Read-Host 'Was OS Type shown as Windows UEFI mode? YES, NO or UNKNOWN'
  $report=New-InspectionReport $comparison $noSave $menu $os
  $path=Join-Path $result.OutputFolder 'inspection-check.json'
  $report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding utf8
  Write-Host ('Return only reviewed '+$path+'. Keep baseline/receipt private. No further firmware visit, setting change or EFI run authorized.')
  exit
 }
 Write-Host 'OPTIONAL ONE attended read-only firmware-menu inspection, ASUS TUF GAMING B550M-E BIOS4101 only.'
 Write-Host 'New access: Windows reads/hashes PUBLIC PK/KEK/db/dbx locally, then YOU may manually enter firmware setup and inspect Boot/Secure Boot/OS Type.'
 Write-Host 'No settings/key/encryption/CSM/TPM changes; do not save. No USB, EFI application, policy toggle, automatic reboot/retry or rollback.'
 Write-Host 'Firmware/display/input or Windows return may hang; recovery is unverified. You may cancel without entering firmware.'
 Write-Host 'If input/display hangs, power off and use normal Windows Boot Manager once. If recovery fails, stop; no CMOS/TPM/key reset or repeat.'
 if((Read-Host 'Only if you accept that exact inspection-only boundary, type INSPECT-ONLY') -cne 'INSPECT-ONLY'){throw 'Stopped; no inspection accepted.'}
 $result=& (Join-Path $PSScriptRoot 'test-policy-baseline.ps1') -Mode Record -Machine $Machine -PassThru
 if(!$? -or !$result -or !(Test-Path -LiteralPath $result.BaselinePath)){throw 'Baseline unavailable; do not enter firmware.'}
 $receipt=[ordered]@{Format=1;Machine=$Machine;Scope='firmware-menu-inspection-no-save';BaselineSha256=(Get-FileHash -LiteralPath $result.BaselinePath -Algorithm SHA256).Hash.ToLowerInvariant()}
 $receipt|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $result.OutputFolder 'inspection-receipt.json') -Encoding utf8
 Write-Host 'BASELINE READY. Save this local folder path. Do not share baseline.json or inspection-receipt.json.'
 Write-Host 'If you still accept: manually restart once and press Delete to enter ASUS setup. Inspect Boot > Secure Boot > OS Type only.'
 Write-Host 'Do not select another value or touch Key Management/CSM/TPM. If labels differ or anything is uncertain, stop inspecting.'
 Write-Host 'Exit with Discard Changes and Exit; cancel any Save prompt. Return to normal Windows without saving.'
 Write-Host 'Then run this same script with -Verify, enter the original local folder, and answer YES/NO/UNKNOWN. Return inspection-check.json only.'
}catch{Write-Error 'Inspection preparation/verification stopped. Keep firmware/settings and original local files unchanged. Do not enter/re-enter firmware or share baseline/provider errors.';exit 1}
