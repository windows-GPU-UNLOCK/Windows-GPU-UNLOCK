# Read-only baseline data, never a policy-change or hardware authorization.
function Get-GuPolicyHash([byte[]]$Bytes){
 $h=[Security.Cryptography.SHA256]::Create()
 try{([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Convert-GuPublicVariableAttributes($Value){
 if($null -eq $Value){throw 'Missing public variable attributes.'}
 if($Value.GetType().FullName -ceq 'Microsoft.SecureBoot.Commands.UEFIEnvironmentVariableAttributes'){
  # The native cmdlet returns a wrapper, not an integer or enum.
  $Value=$Value.Attributes
  if($Value -isnot [uint64] -or $Value -gt [uint32]::MaxValue){throw 'Invalid native public variable attributes.'}
 }elseif($Value -isnot [uint32] -and $Value -isnot [int]){throw 'Unknown public variable attributes type.'}
 try{return [Convert]::ToUInt32($Value)}catch{throw 'Invalid public variable attributes range.'}
}
function New-GuPolicyBaseline([string]$Machine,[string]$ConfigurationSha,[bool]$SecureBoot,$Encryption,$BootManager,[scriptblock]$ReadVariable){
 if($Machine -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or $ConfigurationSha -cnotmatch '^[0-9a-f]{64}$' -or !$SecureBoot){throw 'Baseline needs an exact configuration and enabled Secure Boot.'}
 Assert-GuDecryptedVolume {$Encryption}
 if($BootManager.ReadStatus -cne 'observed' -or $BootManager.ApplicationPathState -cne 'standard-windows-uefi'){throw 'Standard Windows boot-manager observation unavailable.'}
 $vars=[ordered]@{}
 foreach($name in @('PK','KEK','db','dbx')){
  try{$v=& $ReadVariable $name}catch{throw 'A public Secure Boot variable could not be read; baseline not recorded.'}
  if($v.Bytes -isnot [byte[]] -or !$v.Bytes.Length -or $v.Bytes.Length -gt 4MB){throw 'Invalid public variable observation.'}
  $attributes=Convert-GuPublicVariableAttributes $v.Attributes
  $vars[$name]=[ordered]@{Sha256=(Get-GuPolicyHash $v.Bytes);Bytes=$v.Bytes.Length;Attributes=[long]$attributes}
 }
 return [ordered]@{Format=1;Machine=$Machine;ConfigurationSha256=$ConfigurationSha;SecureBootEnabled=$true;SystemVolumeFullyDecrypted=$true;StandardWindowsPathObserved=$true;PublicVariables=$vars}
}
function Test-GuPolicyBaselineShape($Value){
 if(!$Value -or @($Value.PSObject.Properties).Count -ne 7){return $false}
 if($Value.Format -ne 1 -or $Value.Machine -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or $Value.ConfigurationSha256 -cnotmatch '^[0-9a-f]{64}$'){return $false}
 foreach($name in @('SecureBootEnabled','SystemVolumeFullyDecrypted','StandardWindowsPathObserved')){if($Value.$name -isnot [bool] -or !$Value.$name){return $false}}
 $keys=@($Value.PublicVariables.PSObject.Properties.Name)
 if($keys.Count -ne 4 -or @($keys|Where-Object {$_ -cnotin @('PK','KEK','db','dbx')}).Count){return $false}
 foreach($name in $keys){
  $v=$Value.PublicVariables.$name
  if(@($v.PSObject.Properties).Count -ne 3 -or $v.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or
    ($v.Bytes -isnot [int] -and $v.Bytes -isnot [long]) -or $v.Bytes -lt 1 -or $v.Bytes -gt 4MB -or
    ($v.Attributes -isnot [int] -and $v.Attributes -isnot [long]) -or $v.Attributes -lt 0 -or $v.Attributes -gt [uint32]::MaxValue){return $false}
 }
 return $true
}
function Compare-GuPolicyBaseline($Before,$After){
 $r=[ordered]@{Test='public-boot-policy-baseline-v1';Status='invalid-or-unavailable';ExactConfigurationUnchanged=$false;PublicVariablesUnchanged=$false;EnabledDecryptedWindowsPathObserved=$false;RawVariablesExported=$false;PrivateKeysRead=$false;RecoveryVerified=$false;FirmwareTrustEstablished=$false;PolicyChangesPerformed=$false;HardwareTested=$false;WriteEligible=$false}
 if(!(Test-GuPolicyBaselineShape $Before) -or !(Test-GuPolicyBaselineShape $After)){return $r}
 $r.ExactConfigurationUnchanged=$Before.Machine -ceq $After.Machine -and $Before.ConfigurationSha256 -ceq $After.ConfigurationSha256
 $r.PublicVariablesUnchanged=$true
 foreach($name in @('PK','KEK','db','dbx')){
  foreach($field in @('Sha256','Bytes','Attributes')){if($Before.PublicVariables.$name.$field -cne $After.PublicVariables.$name.$field){$r.PublicVariablesUnchanged=$false}}
 }
 $r.EnabledDecryptedWindowsPathObserved=$true
 $r.Status=if($r.ExactConfigurationUnchanged -and $r.PublicVariablesUnchanged){'observations-match'}else{'observations-differ'}
 return $r
}
