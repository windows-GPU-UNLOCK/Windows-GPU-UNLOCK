# Windows-only setup diagnostics. No device, boot or firmware writes.
[CmdletBinding()]
param([Alias('SelfTest')][switch]$PreflightSelfTest,
      [Alias('ExpectedDevice')][ValidatePattern('^(?:[0-9A-Fa-f]{4})?$')][string]$PreflightExpectedDevice,
      [Alias('ExpectedSubsystem')][ValidatePattern('^(?:[0-9A-Fa-f]{8})?$')][string]$PreflightExpectedSubsystem)
if($MyInvocation.InvocationName -ne '.'){$ErrorActionPreference='Stop'}
. (Join-Path $PSScriptRoot '../research/profile/encryption-state.ps1')
function Get-PreflightEncryption([scriptblock]$Query) {
 $unknown=[ordered]@{ReadStatus='unknown';ProtectionState='unknown';ConversionState='unknown';EncryptionPercentage=$null;FullyDecryptedObserved=$false}
 try{
  $state=& $Query
  if($state.ReadStatus -cnotin @('observed','unavailable','unknown') -or
     $state.ProtectionState -cnotin @('off','on','unknown') -or
     $state.ConversionState -cnotin @('fully-decrypted','fully-encrypted','encrypting','decrypting','encryption-paused','decryption-paused','unknown')){return $unknown}
  if($state.ReadStatus -cne 'observed'){return $unknown}
  if(($state.EncryptionPercentage -isnot [int] -and $state.EncryptionPercentage -isnot [long]) -or $state.EncryptionPercentage -lt 0 -or $state.EncryptionPercentage -gt 100 -or $state.FullyDecryptedObserved -isnot [bool]){return $unknown}
  # Only bounded status fields: never copy provider objects/keys/identifiers.
  return [ordered]@{ReadStatus='observed';ProtectionState=$state.ProtectionState;ConversionState=$state.ConversionState;EncryptionPercentage=$state.EncryptionPercentage;FullyDecryptedObserved=($state.ProtectionState -ceq 'off' -and $state.ConversionState -ceq 'fully-decrypted' -and $state.EncryptionPercentage -eq 0 -and $state.FullyDecryptedObserved)}
 }catch{return $unknown}
}
function Public-DriverLabel($Value) {
 if($Value -isnot [string] -or $Value.Length -gt 128 -or $Value -match '[\\/:@\x00-\x1f]'){return $null}
 return $Value
}
function Get-PreflightReport([bool]$Elevated,[scriptblock]$QuerySecureBoot,$Video,$Drivers,[string]$TargetDevice,[string]$TargetSubsystem,[scriptblock]$QueryEncryption={$null}) {
 $secure=[ordered]@{State='unknown';ErrorCategory=$null;HResult=$null}
 try {
  $value=& $QuerySecureBoot
  if($value -isnot [bool]){throw 'Unexpected query result.'}
  $secure.State=if($value){'enabled'}else{'disabled'}
 } catch {
  $secure.ErrorCategory=[string]$_.CategoryInfo.Category
  $secure.HResult='0x'+([Convert]::ToString([int]$_.Exception.HResult,16)).PadLeft(8,'0')
 }
 $adapters=@();$index=0
 foreach($v in $Video){
  $token=$null
  if([string]$v.PNPDeviceID -match '^([A-Za-z][A-Za-z0-9_-]{0,31})\\'){$token=$Matches[1]}
  $pci=$null
  if([string]$v.PNPDeviceID -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{8})(?:&|\\|$)'){
   $pci=[ordered]@{Vendor=$Matches[1];Device=$Matches[2];Subsystem=$Matches[3]}
  }
  $matchesDriver=@($Drivers | Where-Object {$_.DeviceID -and $_.DeviceID -ceq $v.PNPDeviceID})
  $details=@($matchesDriver | ForEach-Object {
   [ordered]@{Provider=(Public-DriverLabel $_.DriverProviderName);Manufacturer=(Public-DriverLabel $_.Manufacturer);
    Version=(Public-DriverLabel $_.DriverVersion);Inf=(Public-DriverLabel $_.InfName);Signed=($_.IsSigned -eq $true)}
  })
  $adapters += [ordered]@{Index=$index;EnumeratorToken=$token;Pci=$pci;MatchingDriverCount=$details.Count;Drivers=$details};$index++
 }
 $targetMatches=@($adapters | Where-Object {$_.Pci -and $_.Pci.Vendor -ieq '10DE' -and $_.Pci.Device -ieq $TargetDevice -and (!$TargetSubsystem -or $_.Pci.Subsystem -ieq $TargetSubsystem)})
 $target=if($TargetDevice){[ordered]@{Vendor='10DE';Device=$TargetDevice.ToUpperInvariant();ExpectedSubsystem=$(if($TargetSubsystem){$TargetSubsystem.ToUpperInvariant()}else{$null});MatchCount=$targetMatches.Count;UniqueInventoryMatch=($targetMatches.Count -eq 1)}}else{$null}
 return [ordered]@{SchemaVersion=3;Target=$target;Elevated=$Elevated;SecureBoot=$secure;SystemVolumeEncryption=(Get-PreflightEncryption $QueryEncryption);DisplayAdapters=$adapters;
   HardwareTested=$false;WriteEligible=$false;Next='Keep EFI preparation stopped until reviewed. No settings changes or boot.'}
}
# Importing the helpers never queries Windows or creates a report directory.
if($MyInvocation.InvocationName -eq '.'){return}
if($PreflightSelfTest){
 $video=@([pscustomobject]@{PNPDeviceID='LCI\PRIVATE'})
 $drivers=@([pscustomobject]@{DeviceID='LCI\PRIVATE';DriverProviderName='Example Display';Manufacturer='Example';DriverVersion='1.2.3';InfName='oem1.inf';IsSigned=$true},[pscustomobject]@{DeviceID='OTHER\PRIVATE';DriverProviderName='WRONG'})
 foreach($enabled in @($true,$false)){
  $query={ $enabled }.GetNewClosure();$r=Get-PreflightReport $false $query $video $drivers
  $expected=if($enabled){'enabled'}else{'disabled'}
  if($r.SecureBoot.State -ne $expected -or $r.DisplayAdapters[0].MatchingDriverCount -ne 1 -or $r.DisplayAdapters[0].Drivers[0].Provider -ne 'Example Display'){throw 'Preflight state/driver regression'}
 }
 $r=Get-PreflightReport $false {throw 'PRIVATE ERROR PATH'} $video $drivers
 $json=$r|ConvertTo-Json -Depth 8
 if($r.SecureBoot.State -ne 'unknown' -or $json.Contains('PRIVATE') -or $json.Contains('WRONG') -or (Public-DriverLabel 'C:\PRIVATE\FILE')){throw 'Preflight failure/redaction regression'}
 $r=Get-PreflightReport $true {'false'} @() @()
 if($r.SecureBoot.State -ne 'unknown' -or $r.WriteEligible){throw 'Unknown state must not become disabled'}
 $sample='PCI'+[char]92+'VEN_10DE&DEV_2489&SUBSYS_12341569&REV_A1'+[char]92+'PRIVATE'
 $v=@([pscustomobject]@{PNPDeviceID=$sample})
 $r=Get-PreflightReport $false {$true} $v @() '2489'
 if(!$r.Target.UniqueInventoryMatch -or $r.DisplayAdapters[0].Pci.Subsystem -cne '12341569' -or ($r|ConvertTo-Json -Depth 8).Contains('PRIVATE')){throw 'Target inventory/privacy regression'}
 $r=Get-PreflightReport $false {$true} @($v+$v) @() '2489'
 if($r.Target.UniqueInventoryMatch -or $r.Target.MatchCount -ne 2){throw 'Duplicate targets must remain ambiguous'}
 $r=Get-PreflightReport $false {$true} $v @() '2204'
 if($r.Target.UniqueInventoryMatch -or $r.Target.MatchCount -ne 0){throw 'Wrong target accepted'}
 $other=[pscustomobject]@{PNPDeviceID=$sample.Replace('12341569','38961462')}
 $r=Get-PreflightReport $false {$false} @($v+$other) @() '2489' '38961462'
 if(!$r.Target.UniqueInventoryMatch -or $r.Target.ExpectedSubsystem -cne '38961462'){throw 'Exact subsystem match failed'}
 $r=Get-PreflightReport $false {$false} @($other,$other) @() '2489' '38961462'
 if($r.Target.UniqueInventoryMatch -or $r.Target.MatchCount -ne 2){throw 'Duplicate subsystem accepted'}
 $r=Get-PreflightReport $false {$false} $v @() '2489' '38961462'
 if($r.Target.UniqueInventoryMatch -or $r.Target.MatchCount -ne 0){throw 'Wrong subsystem accepted'}
 $observed={ [pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-encrypted';EncryptionPercentage=100;FullyDecryptedObserved=$false;RecoveryPassword='PRIVATE'} }
 $r=Get-PreflightReport $false {$false} @() @() '2504' '397D1462' $observed
 if($r.SystemVolumeEncryption.FullyDecryptedObserved -or $r.SystemVolumeEncryption.ConversionState -cne 'fully-encrypted' -or ($r|ConvertTo-Json -Depth 8).Contains('PRIVATE')){throw 'Protection-off encryption/privacy regression'}
 $r=Get-PreflightReport $false {$false} @() @() '2504' '397D1462' {throw 'PRIVATE-PROVIDER-ERROR'}
 if($r.SystemVolumeEncryption.ReadStatus -cne 'unknown' -or ($r|ConvertTo-Json -Depth 8).Contains('PRIVATE')){throw 'Unavailable encryption provider/privacy regression'}
 $r=Get-PreflightReport $false {$false} @() @() '2504' '397D1462' {[pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage=0;FullyDecryptedObserved=$true}}
 if(!$r.SystemVolumeEncryption.FullyDecryptedObserved -or $r.WriteEligible){throw 'Decrypted observation/admission regression'}
 Write-Host 'PASS: enabled/disabled/unknown states, driver association, redaction, non-boolean refusal.';exit
}
if($PreflightExpectedSubsystem -and !$PreflightExpectedDevice){throw '-ExpectedSubsystem requires -ExpectedDevice.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$elevated=([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$report=Get-PreflightReport $elevated {Confirm-SecureBootUEFI -ErrorAction Stop} @(Get-CimInstance Win32_VideoController) @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'") $PreflightExpectedDevice $PreflightExpectedSubsystem {Read-EncryptionStatus}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$out=Join-Path $docs ('GPU-Unlock-Preflight-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $out|Out-Null
$path=Join-Path $out 'windows-preflight.json';$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Review and return only '+$path+'. Keep EFI preparation stopped; do not change settings or boot.')
