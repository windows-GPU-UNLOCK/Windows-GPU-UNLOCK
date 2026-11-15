# Offline preparation-gate regressions. No system queries, staging or hardware.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'encryption-state.ps1')
function Observe($Protection,$Conversion,$Percent){
 Convert-EncryptionStatus ([pscustomobject]@{ReturnValue=0;ProtectionStatus=$Protection}) ([pscustomobject]@{ReturnValue=0;ConversionStatus=$Conversion;EncryptionPercentage=$Percent})
}
$script:value=Observe 0 0 0
Assert-GuDecryptedVolume {$script:value}
$count=1
foreach($case in @(@(0,1,100),@(1,1,100),@(0,2,20),@(0,3,20),@(0,4,20),@(0,5,20),@(2,0,0))){
 $script:value=Observe $case[0] $case[1] $case[2];$refused=$false
 try{Assert-GuDecryptedVolume {$script:value}}catch{$refused=$true}
 if(!$refused){throw 'Encrypted, transitional or unknown volume allowed.'}
 $count++
}
foreach($state in @(
 @{ReadStatus='unavailable';FullyDecryptedObserved=$false},
 @{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage='0';FullyDecryptedObserved=$true},
 @{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage=0;FullyDecryptedObserved='true'})){
 $script:value=$state;$refused=$false
 try{Assert-GuDecryptedVolume {$script:value}}catch{$refused=$true}
 if(!$refused){throw 'Unverified or malformed encryption observation allowed.'}
 $count++
}
$refused=$false;try{Assert-GuDecryptedVolume {throw 'PRIVATE-ERROR'}}catch{$refused=$true;if($_.Exception.Message.Contains('PRIVATE')){throw 'Raw provider error leaked'}}
if(!$refused){throw 'Failed read allowed'}
# A permitted initial read cannot authorize a later changed state.
$script:value=Observe 0 0 0;Assert-GuDecryptedVolume {$script:value}
$script:value=Observe 0 1 100;$refused=$false
try{Assert-GuDecryptedVolume {$script:value}}catch{$refused=$true}
if(!$refused){throw 'Stale initial observation allowed'}
Write-Host ('PASS: '+($count+2)+' encryption gate cases, including protection-off encrypted and changed-state recheck. No system access.')
