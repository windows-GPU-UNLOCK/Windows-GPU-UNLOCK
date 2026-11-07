# Prerequisite observations only. No encryption, policy, boot or device changes.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../research/profile/encryption-state.ps1')
function Convert-BootManagerObservation([string]$Text,[int]$Exit){
 $pattern='(?im)^\s*\S+\s+[\\/]EFI[\\/]Microsoft[\\/]Boot[\\/]bootmgfw\.efi\s*$'
 return [ordered]@{QuerySucceeded=($Exit -eq 0);StandardUefiPathObserved=($Exit -eq 0 -and [regex]::IsMatch($Text,$pattern));RawBcdExported=$false;BootRecoveryVerified=$false}
}
function Read-BootManagerObservation {
 try{
  $p=New-Object Diagnostics.Process
  $p.StartInfo.FileName=Join-Path $env:SystemRoot 'System32/bcdedit.exe'
  $p.StartInfo.Arguments='/enum {bootmgr}'
  $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true
  $p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
  $p.Start()|Out-Null;$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
  if(!$p.WaitForExit(15000)){$p.Kill();throw 'Query timeout.'}
  return Convert-BootManagerObservation $stdout.Result $p.ExitCode
 }catch{return Convert-BootManagerObservation '' -1}finally{if($p){$p.Dispose()}}
}
# Dot sourcing exposes read/classification functions without running queries or writing a report.
if($MyInvocation.InvocationName -eq '.'){return}
if($SelfTest){
 $p=[pscustomobject]@{ReturnValue=0;ProtectionStatus=0};$c=[pscustomobject]@{ReturnValue=0;ConversionStatus=0;EncryptionPercentage=0}
 if(!(Convert-EncryptionStatus $p $c).FullyDecryptedObserved){throw 'Decrypted observation lost.'}
 $c.ConversionStatus=1;$c.EncryptionPercentage=100
 if((Convert-EncryptionStatus $p $c).FullyDecryptedObserved){throw 'Suspended encryption confused with decrypted.'}
 $p.ProtectionStatus=1;if((Convert-EncryptionStatus $p $c).FullyDecryptedObserved){throw 'Protected volume accepted.'}
 $p.ReturnValue=1;if((Convert-EncryptionStatus $p $c).ReadStatus -cne 'unknown'){throw 'Query failure became known.'}
 $p.ReturnValue=0;$p.ProtectionStatus=0;$c.ConversionStatus=0;$c.EncryptionPercentage='0'
 if((Convert-EncryptionStatus $p $c).ReadStatus -cne 'unknown'){throw 'Non-integer status became known.'}
 $path='path '+[char]92+'EFI'+[char]92+'Microsoft'+[char]92+'Boot'+[char]92+'bootmgfw.efi'
 $r=Convert-BootManagerObservation ('PRIVATE-IDENTIFIER'+[Environment]::NewLine+$path) 0
 if(!$r.StandardUefiPathObserved -or $r.BootRecoveryVerified -or ($r|ConvertTo-Json).Contains('PRIVATE')){throw 'BCD scope/privacy regression.'}
 if((Convert-BootManagerObservation $path 1).StandardUefiPathObserved -or (Convert-BootManagerObservation 'PRIVATE' 0).StandardUefiPathObserved){throw 'Failed/missing path accepted.'}
 $script:ReadMethods=@()
 function Get-CimInstance {param($Namespace,$ClassName,$Filter,$ErrorAction);[pscustomobject]@{Unused='PRIVATE-VOLUME-ID'}}
 function Invoke-CimMethod {
  param($InputObject,$MethodName,$ErrorAction)
  $script:ReadMethods += $MethodName
  if($MethodName -ceq 'GetProtectionStatus'){return [pscustomobject]@{ReturnValue=0;ProtectionStatus=0}}
  if($MethodName -ceq 'GetConversionStatus'){return [pscustomobject]@{ReturnValue=0;ConversionStatus=0;EncryptionPercentage=0}}
  throw 'Unexpected method'
 }
 $r=Read-EncryptionStatus
 if(!$r.FullyDecryptedObserved -or $script:ReadMethods.Count -ne 2 -or ($r|ConvertTo-Json).Contains('PRIVATE')){throw 'Read-only provider query regression.'}
 function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction);throw 'PRIVATE-ERROR-PATH'}
 $r=Read-EncryptionStatus
 if($r.ReadStatus -cne 'unavailable' -or $r.FullyDecryptedObserved -or ($r|ConvertTo-Json).Contains('PRIVATE')){throw 'Failed provider query became known or leaked details.'}
 Write-Host 'PASS: decrypted versus suspended/encrypted/unknown, BCD observation/failure and privacy. No system queries.';exit
}
$secure='unknown';try{$s=Confirm-SecureBootUEFI -ErrorAction Stop;if($s -is [bool]){$secure=if($s){'enabled'}else{'disabled'}}}catch{}
$report=[ordered]@{Test='attended-prerequisites-v1';SecureBootState=$secure;Encryption=(Read-EncryptionStatus);BootManager=(Read-BootManagerObservation);
 RecoveryKeysRead=$false;EncryptionChangesPerformed=$false;PolicyChangesPerformed=$false;BootRecoveryVerified=$false;FirmwareTrustEstablished=$false;HardwareTested=$false;WriteEligible=$false;
 Next='Prerequisite observations only. Keep Secure Boot, encryption, keys, cables and settings unchanged. No EFI preparation, staging or boot is authorized.'}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$out=Join-Path $docs ('GPU-Unlock-Prerequisites-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $out|Out-Null
$path=Join-Path $out 'attended-prerequisites.json';$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only reviewed '+$path+'. No settings changes or EFI boot are authorized.')
