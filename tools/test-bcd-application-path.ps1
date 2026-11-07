# Reads one application-path element from the current BCD store; no BCD changes.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
function Get-BcdPathObservation([scriptblock]$Query){
 $r=[ordered]@{ReadStatus='unavailable';ApplicationPathState='unknown';RawPathExported=$false;BootRecoveryVerified=$false}
 try{
  $value=& $Query
  if($value.Success -isnot [bool] -or !$value.Success){return $r}
  $r.ReadStatus='observed'
  if($value.Path -isnot [string] -or !$value.Path -or $value.Path.Length -gt 2048){$r.ApplicationPathState='missing-or-invalid';return $r}
  if($value.Path -ieq '\EFI\Microsoft\Boot\bootmgfw.efi'){$r.ApplicationPathState='standard-windows-uefi'}
  else{$r.ApplicationPathState='other'}
 }catch{}
 return $r
}
function Read-BcdApplicationPath {
 # Only OpenStore, OpenObject and GetElement are permitted. No enumeration or setters.
 $store=Invoke-CimMethod -Namespace root/wmi -ClassName BcdStore -MethodName OpenStore -Arguments @{File=''} -ErrorAction Stop
 if($store.ReturnValue -isnot [bool] -or !$store.ReturnValue){return @{Success=$false}}
 $obj=Invoke-CimMethod -InputObject $store.Store -MethodName OpenObject -Arguments @{Id='{9dea862c-5cdd-4e70-acc1-f32b344d4795}'} -ErrorAction Stop
 if($obj.ReturnValue -isnot [bool] -or !$obj.ReturnValue){return @{Success=$false}}
 $element=Invoke-CimMethod -InputObject $obj.Object -MethodName GetElement -Arguments @{Type=[uint32]0x12000002} -ErrorAction Stop
 if($element.ReturnValue -isnot [bool] -or !$element.ReturnValue){return @{Success=$false}}
 return @{Success=$true;Path=$element.Element.String}
}
if($MyInvocation.InvocationName -eq '.'){return}
if($SelfTest){
 $r=Get-BcdPathObservation { @{Success=$true;Path='\EFI\Microsoft\Boot\bootmgfw.efi'} }
 if($r.ApplicationPathState -cne 'standard-windows-uefi' -or $r.BootRecoveryVerified){throw 'Standard path classification failed.'}
 $r=Get-BcdPathObservation { @{Success=$true;Path='C:\PRIVATE\custom.efi'} }
 if($r.ApplicationPathState -cne 'other' -or ($r|ConvertTo-Json).Contains('PRIVATE')){throw 'Other path leaked or misclassified.'}
 foreach($v in @($null,42,'')){
  $r=Get-BcdPathObservation { @{Success=$true;Path=$v} }
  if($r.ApplicationPathState -cne 'missing-or-invalid'){throw 'Invalid path accepted.'}
 }
 foreach($v in @($false,1,'true')){
  $r=Get-BcdPathObservation { @{Success=$v;Path='\EFI\Microsoft\Boot\bootmgfw.efi'} }
  if($r.ReadStatus -cne 'unavailable'){throw 'Failed or nonboolean provider status accepted.'}
 }
 $r=Get-BcdPathObservation {throw 'PRIVATE-PATH-ERROR'}
 if($r.ReadStatus -cne 'unavailable' -or ($r|ConvertTo-Json).Contains('PRIVATE')){throw 'Error leaked.'}
 $script:Methods=@()
 function Invoke-CimMethod {
  param($Namespace,$ClassName,$MethodName,$Arguments,$InputObject,$ErrorAction)
  $script:Methods += $MethodName
  switch($MethodName){
   OpenStore {if($ClassName -cne 'BcdStore' -or $Arguments.File -cne ''){throw 'Unexpected store'};return @{ReturnValue=$true;Store='MOCK-STORE'}}
   OpenObject {if($Arguments.Id -cne '{9dea862c-5cdd-4e70-acc1-f32b344d4795}'){throw 'Unexpected object'};return @{ReturnValue=$true;Object='MOCK-OBJECT'}}
   GetElement {if($Arguments.Type -ne 0x12000002){throw 'Unexpected element'};return @{ReturnValue=$true;Element=@{String='\EFI\Microsoft\Boot\bootmgfw.efi'}}}
   default {throw 'Unexpected method'}
  }
 }
 $r=Get-BcdPathObservation {Read-BcdApplicationPath}
 if($r.ApplicationPathState -cne 'standard-windows-uefi' -or ($script:Methods -join ',') -cne 'OpenStore,OpenObject,GetElement'){throw 'Provider call contract failed.'}
 Write-Host 'PASS: fixed read-only BCD calls, path classification, strict provider status, unknown and privacy.';exit
}
$r=Get-BcdPathObservation {Read-BcdApplicationPath}
$report=[ordered]@{Test='bcd-application-path-v1';BootManager=$r;BcdChangesPerformed=$false;FirmwareChangesPerformed=$false;HardwareTested=$false;WriteEligible=$false}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$folder=Join-Path $docs ('GPU-Unlock-Bcd-Path-'+[guid]::NewGuid().ToString('N').Substring(0,8));New-Item -ItemType Directory -Path $folder|Out-Null
$path=Join-Path $folder 'bcd-path.json';$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding utf8
Write-Host ('Return only reviewed '+$path+'. No boot, BCD or firmware changes.')
