# Default is offline synthetic testing. Record/Verify only read Windows state.
[CmdletBinding()]
param([ValidateSet('SelfTest','Record','Verify')][string]$Mode='SelfTest',[string]$Machine,[string]$Baseline,[switch]$PassThru)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'encryption-state.ps1')
. (Join-Path $PSScriptRoot 'policy-baseline.ps1')
function JsonCopy($Value){$Value|ConvertTo-Json -Depth 10|ConvertFrom-Json}
if($Mode -ceq 'SelfTest'){
 $enc=[pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage=0;FullyDecryptedObserved=$true}
 $bcd=[pscustomobject]@{ReadStatus='observed';ApplicationPathState='standard-windows-uefi'}
 $query={param($name) [pscustomobject]@{Bytes=[byte[]](1,2,3);Attributes=[uint32]7}}
 foreach($bad in @('7',-1,$null,[DayOfWeek]::Monday)){
  $refused=$false;try{Convert-GuPublicVariableAttributes $bad|Out-Null}catch{$refused=$true}
  if(!$refused){throw 'Invalid attribute type/range accepted'}
 }
 if((Convert-GuPublicVariableAttributes ([uint32]7)) -ne 7){throw 'Numeric attributes changed'}
 # Reflection reads installed cmdlet metadata, not a UEFI variable.
 $cmd=Get-Command Get-SecureBootUEFI -ErrorAction SilentlyContinue
 if($cmd -and $cmd.ImplementingType){
  $variableType=$cmd.ImplementingType.Assembly.GetType('Microsoft.SecureBoot.Commands.UEFIEnvironmentVariable')
  $attributeType=$variableType.GetProperty('Attributes').PropertyType
  $nativeAttribute=[Activator]::CreateInstance($attributeType,[object[]]@([uint64]7))
  if((Convert-GuPublicVariableAttributes $nativeAttribute) -ne 7){throw 'Installed SecureBoot attribute wrapper rejected'}
  $nativeBaseline=JsonCopy (New-GuPolicyBaseline 'issue135' ('a'*64) $true $enc $bcd {param($name) [pscustomobject]@{Bytes=[byte[]](1,2,3);Attributes=$nativeAttribute}})
  if($nativeBaseline.PublicVariables.db.Attributes -ne 7){throw 'Native attribute object did not survive baseline serialization'}
  $overflowAttribute=[Activator]::CreateInstance($attributeType,[object[]]@([uint64]::MaxValue))
  $refused=$false;try{Convert-GuPublicVariableAttributes $overflowAttribute|Out-Null}catch{$refused=$true}
  if(!$refused){throw 'Native attribute overflow accepted'}
  Write-Host 'PASS: installed SecureBoot attribute metadata; no firmware variable read.'
 }
 $before=JsonCopy (New-GuPolicyBaseline 'issue135' ('a'*64) $true $enc $bcd $query)
 $after=JsonCopy $before
 if((Compare-GuPolicyBaseline $before $after).Status -cne 'observations-match'){throw 'Unchanged observation lost'}
 foreach($name in @('PK','KEK','db','dbx')){
  $changed=JsonCopy $after;$changed.PublicVariables.$name.Sha256='b'*64
  if((Compare-GuPolicyBaseline $before $changed).Status -cne 'observations-differ'){throw 'Changed public variable missed'}
 }
 $attributeChange=JsonCopy $after;$attributeChange.PublicVariables.db.Attributes=8
 if((Compare-GuPolicyBaseline $before $attributeChange).PublicVariablesUnchanged){throw 'Public variable attribute drift missed'}
 $changed=JsonCopy $after;$changed.ConfigurationSha256='b'*64
 if((Compare-GuPolicyBaseline $before $changed).ExactConfigurationUnchanged){throw 'Configuration drift missed'}
 $changed=JsonCopy $after;$changed.PublicVariables.db.Bytes='3'
 if((Compare-GuPolicyBaseline $before $changed).Status -cne 'invalid-or-unavailable'){throw 'Malformed baseline accepted'}
 $refused=$false;try{New-GuPolicyBaseline 'issue135' ('a'*64) $false $enc $bcd $query}catch{$refused=$true};if(!$refused){throw 'Disabled policy baseline accepted'}
 $enc.ConversionState='fully-encrypted';$refused=$false
 try{New-GuPolicyBaseline 'issue135' ('a'*64) $true $enc $bcd $query}catch{$refused=$true};if(!$refused){throw 'Encrypted baseline accepted'}
 # Captured numeric-state regression: encrypted/protection-off cannot record a
 # baseline, regardless of automatic provisioning or the user's intent.
 $captured=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/device-encryption-protection-off.json') -Raw|ConvertFrom-Json
 $script:VariableReads=0;$refused=$false
 try{New-GuPolicyBaseline 'issue135' ('a'*64) $true $captured $bcd {param($name) $script:VariableReads++;throw 'Public variable query should not occur'}}catch{$refused=$true}
 if(!$refused -or $script:VariableReads -ne 0){throw 'Encrypted captured state reached public variable reads'}
 $enc.ConversionState='fully-decrypted';$refused=$false
 try{New-GuPolicyBaseline 'issue135' ('a'*64) $true $enc $bcd {throw 'PRIVATE-ERROR'}}catch{$refused=$true;if($_.Exception.Message.Contains('PRIVATE')){throw 'Provider error leaked'}}
 if(!$refused){throw 'Missing variable accepted'}
 $r=Compare-GuPolicyBaseline $before $after;$json=$r|ConvertTo-Json
 if($json.Contains(('a'*64)) -or $json.Contains('Sha256') -or $r.RecoveryVerified -or $r.WriteEligible){throw 'Fingerprint leaked or eligibility granted'}
 # Real file roundtrip exercises the same private-baseline serialization as Record/Verify.
 $path=Join-Path ([IO.Path]::GetTempPath()) ('policy-baseline-test-'+[guid]::NewGuid().ToString('N')+'.json')
 $before|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $path -Encoding utf8
 $roundtrip=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
 if((Compare-GuPolicyBaseline $before $roundtrip).Status -cne 'observations-match'){throw 'Serialized baseline changed'}
 Write-Host 'PASS: public-variable/configuration drift, malformed/disabled/encrypted/unavailable refusals, privacy, captured-state early stop and file roundtrip. No Windows queries.';exit
}
try {
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if($Mode -ceq 'Verify'){
 if(!$Baseline){throw 'Provide the original local baseline.json; never share it.'}
 $item=Get-Item -LiteralPath $Baseline
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 64KB){throw 'Baseline must be a small regular local file.'}
 $before=Get-Content -LiteralPath $Baseline -Raw|ConvertFrom-Json
 if(!(Test-GuPolicyBaselineShape $before)){throw 'Invalid baseline; do not repair, change settings or proceed.'}
 $Machine=$before.Machine
}
if($Machine -cnotmatch '^[a-z][a-z0-9-]{0,63}$'){throw 'An exact reviewed machine configuration is required.'}
# Preserve chosen ID across dot-sourced preparation parameter defaults.
$chosen=$Machine
. (Join-Path $PSScriptRoot 'prepare-graph.ps1')
$configuration=Read-GraphConfiguration $chosen
$drivers=@();if(@($configuration.KnownNonPciAdapters|Where-Object {$_}).Count){$drivers=@(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'")}
Assert-GraphMachine $chosen (Get-CimInstance Win32_BaseBoard) (Get-CimInstance Win32_BIOS) (Get-CimInstance Win32_Processor) @(Get-CimInstance Win32_VideoController) $drivers
. (Join-Path $repo 'tools/test-bcd-application-path.ps1')
$bcd=Get-BcdPathObservation {Read-BcdApplicationPath}
$secure=Confirm-SecureBootUEFI -ErrorAction Stop
if($secure -isnot [bool]){throw 'Secure Boot state unknown.'}
$current=JsonCopy (New-GuPolicyBaseline $chosen (Get-GraphHash (Join-Path $PSScriptRoot ('graph-configurations/'+$chosen+'.json'))) $secure (Read-EncryptionStatus) $bcd {param($name) Get-SecureBootUEFI -Name $name -ErrorAction Stop})
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents unavailable.'}
$out=Join-Path $docs ('GPU-Unlock-Policy-Baseline-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $out|Out-Null
if($Mode -ceq 'Record'){
 $current|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $out 'baseline.json') -Encoding utf8
 $report=Compare-GuPolicyBaseline $current $current;$report.Status='baseline-recorded-not-restoration-tested'
}else{$report=Compare-GuPolicyBaseline $before $current}
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $out 'policy-check.json') -Encoding utf8
Write-Host ('Local folder: '+$out+'. Keep baseline.json private/local. Only policy-check.json is shareable after review. No settings changes or EFI authorization.')
if($PassThru){[pscustomobject]@{OutputFolder=$out;BaselinePath=(Join-Path $out 'baseline.json');ReportPath=(Join-Path $out 'policy-check.json')}}

}catch{Write-Error 'Read-only policy baseline could not be completed. Preserve existing files and settings; do not share raw provider errors or baseline.json.';exit 1}
