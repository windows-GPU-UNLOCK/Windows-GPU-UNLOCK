# Shared read-only system-volume encryption state and attended preparation gate.
function Convert-EncryptionStatus($Protection,$Conversion){
 $r=[ordered]@{Provider='Win32_EncryptableVolume';ReadStatus='unknown';ProtectionState='unknown';ConversionState='unknown';EncryptionPercentage=$null;FullyDecryptedObserved=$false}
 foreach($value in @($Protection.ReturnValue,$Conversion.ReturnValue,$Protection.ProtectionStatus,$Conversion.ConversionStatus,$Conversion.EncryptionPercentage)){
  if($value -isnot [int] -and $value -isnot [uint32] -and $value -isnot [long] -and $value -isnot [uint64]){return $r}
 }
 if($Protection.ReturnValue -ne 0 -or $Conversion.ReturnValue -ne 0 -or
    $Protection.ProtectionStatus -notin @(0,1,2) -or $Conversion.ConversionStatus -notin @(0,1,2,3,4,5) -or
    $Conversion.EncryptionPercentage -isnot [ValueType] -or $Conversion.EncryptionPercentage -lt 0 -or $Conversion.EncryptionPercentage -gt 100){return $r}
 $r.ReadStatus='observed';$r.ProtectionState=@('off','on','unknown')[[int]$Protection.ProtectionStatus]
 $r.ConversionState=@('fully-decrypted','fully-encrypted','encrypting','decrypting','encryption-paused','decryption-paused')[[int]$Conversion.ConversionStatus]
 $r.EncryptionPercentage=[int]$Conversion.EncryptionPercentage
 $r.FullyDecryptedObserved=($Protection.ProtectionStatus -eq 0 -and $Conversion.ConversionStatus -eq 0 -and $Conversion.EncryptionPercentage -eq 0)
 return $r
}
function Read-EncryptionStatus {
 try{
  if($env:SystemDrive -notmatch '^[A-Za-z]:$'){throw 'Unknown system drive.'}
  $v=@(Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter ("DriveLetter='"+$env:SystemDrive+"'") -ErrorAction Stop)
  if($v.Count -ne 1){throw 'Ambiguous volume.'}
  $p=Invoke-CimMethod -InputObject $v[0] -MethodName GetProtectionStatus -ErrorAction Stop
  $c=Invoke-CimMethod -InputObject $v[0] -MethodName GetConversionStatus -ErrorAction Stop
  # Never query protectors, recovery passwords, keys or volume identifiers.
  return Convert-EncryptionStatus $p $c
 }catch{return [ordered]@{Provider='Win32_EncryptableVolume';ReadStatus='unavailable';ProtectionState='unknown';ConversionState='unknown';EncryptionPercentage=$null;FullyDecryptedObserved=$false}}
}
function Assert-GuDecryptedVolume([scriptblock]$ReadStatus={Read-EncryptionStatus}) {
 try {$state=& $ReadStatus} catch {throw 'System-volume encryption state is unavailable. Stop; do not change encryption or settings.'}
 if($state.ReadStatus -cne 'observed' -or $state.ProtectionState -cne 'off' -or
    $state.ConversionState -cne 'fully-decrypted' -or $state.EncryptionPercentage -isnot [int] -or
    $state.EncryptionPercentage -ne 0 -or $state.FullyDecryptedObserved -isnot [bool] -or
    !$state.FullyDecryptedObserved){throw 'This attended preparation requires an observed fully decrypted system volume. Protection off alone is insufficient. Stop; do not suspend, decrypt or change settings for this script.'}
}
