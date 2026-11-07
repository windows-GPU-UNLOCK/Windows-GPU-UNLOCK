# Windows inventory only. No disk, firmware or device changes.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
function Convert-DisplayIdentity($Video) {
 $index=0
 @($Video | ForEach-Object {
  $id=[string]$_.PNPDeviceID
  $bus='missing'
  if($id){$bus='other';foreach($known in @('PCI','ROOT','SWD','USB','DISPLAY')){if($id -match ('^'+$known+'\\')){$bus=$known;break}}}
  # Export only a short bus/enumerator token before the FIRST separator.
  # Never export the rest of an identity, adapter names or instance suffixes.
  $prefix=$null;$shape='missing'
  if($id){
   $shape='unrecognized'
   if($id -match '^([A-Za-z][A-Za-z0-9_-]{0,31})\\'){$prefix=$Matches[1];$shape='token'}
   elseif($id -match '^\{[0-9A-Fa-f-]{36}\}\\'){$shape='guid-prefix'}
  }
  $pci=$null
  if($id -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{8})(?:&|\\|$)'){
   $pci=[ordered]@{Vendor=$Matches[1];Device=$Matches[2];Subsystem=$Matches[3]}
  }
  [pscustomobject]@{Index=$index;Enumerator=$bus;EnumeratorToken=$prefix;IdentityShape=$shape;Pci=$pci};$index++
 })
}
if($SelfTest){
 $v=@([pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_147D10DE&REV_A1\PRIVATE'},[pscustomobject]@{PNPDeviceID='USB\VID_1234&PID_5678\PRIVATE'},[pscustomobject]@{PNPDeviceID=$null},[pscustomobject]@{PNPDeviceID='UNKNOWN\PRIVATE'})
 $r=@(Convert-DisplayIdentity $v);$json=$r|ConvertTo-Json -Depth 5
 if($r.Count -ne 4 -or $r[0].Pci.Device -ne '2204' -or $r[1].Enumerator -ne 'USB' -or $r[2].Enumerator -ne 'missing' -or $r[3].Enumerator -ne 'other' -or $r[3].EnumeratorToken -cne 'UNKNOWN' -or $json.Contains('PRIVATE') -or $json.Contains('1234')){throw 'Identity summary regression'}
 $bad=@(Convert-DisplayIdentity @([pscustomobject]@{PNPDeviceID='C:/PRIVATE/FILE'},[pscustomobject]@{PNPDeviceID='{11111111-2222-3333-4444-555555555555}\PRIVATE'},[pscustomobject]@{PNPDeviceID='UNKNOWN\PRIVATE\EXTRA'}))
 if($bad[0].EnumeratorToken -or $bad[1].EnumeratorToken -or $bad[2].EnumeratorToken -cne 'UNKNOWN' -or ($bad|ConvertTo-Json -Depth 5).Contains('PRIVATE')){throw 'Enumerator prefix redaction regression'}
 Write-Host 'PASS: PCI, USB, missing and unknown identities; instance suffixes excluded.';exit
}
$adapters=@(Convert-DisplayIdentity @(Get-CimInstance Win32_VideoController))
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$folder=Join-Path $docs ('GPU-Unlock-Display-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $folder | Out-Null
$path=Join-Path $folder 'display-identities.json'
[ordered]@{SchemaVersion=2;Adapters=$adapters;HardwareTested=$false;WriteEligible=$false}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only '+$path+'. Do not edit the preparation guard or boot the USB.')
