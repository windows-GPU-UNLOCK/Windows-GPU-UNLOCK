# GPL-2.0-only. Native Windows observations for the shared diagnostics workflow.
# Importing or calling this module never writes reports, stages EFI or changes settings.
. (Join-Path $PSScriptRoot 'test-windows-preflight.ps1')
. (Join-Path $PSScriptRoot 'test-pci-parents.ps1')

function Get-GuDiagnosticQueries {
 return @{
  Board={Get-CimInstance Win32_BaseBoard -Property Manufacturer,Product -ErrorAction Stop}
  Bios={Get-CimInstance Win32_BIOS -Property Manufacturer,SMBIOSBIOSVersion -ErrorAction Stop}
  Cpu={Get-CimInstance Win32_Processor -Property Name,Manufacturer -ErrorAction Stop}
  OperatingSystem={Get-CimInstance Win32_OperatingSystem -Property Caption,Version,BuildNumber,OSArchitecture -ErrorAction Stop}
  Video={Get-CimInstance Win32_VideoController -Property Name,PNPDeviceID,DriverVersion -ErrorAction Stop}
  Drivers={Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'" -Property DeviceID,DriverProviderName,Manufacturer,DriverVersion,InfName,IsSigned -ErrorAction Stop}
  PnpDisplay={Get-PnpDevice -PresentOnly -Class Display -ErrorAction Stop}
  ReadParent={
   param($id)
   $p=Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_Parent -ErrorAction Stop
   if($p.Type -cne 'String' -or $p.Data -isnot [string]){throw 'Parent property unavailable.'}
   $p.Data
  }
  SecureBoot={Confirm-SecureBootUEFI -ErrorAction Stop}
  Encryption={Read-EncryptionStatus}
  Elevated={
   $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
   ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  }
  Architecture={
   $native=if($env:PROCESSOR_ARCHITEW6432){$env:PROCESSOR_ARCHITEW6432}else{$env:PROCESSOR_ARCHITECTURE}
   [pscustomobject]@{Process=$env:PROCESSOR_ARCHITECTURE;Native=$native}
  }
  Firmware={(Get-ComputerInfo -Property BiosFirmwareType -ErrorAction Stop).BiosFirmwareType.ToString()}
  Capabilities={
   $r=[ordered]@{}
   foreach($name in @('Get-CimInstance','Get-PnpDevice','Get-PnpDeviceProperty','Confirm-SecureBootUEFI','Get-Partition','Get-Disk','Get-Volume')){
    $r[$name]=[bool](Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1)
   }
   [pscustomobject]$r
  }
 }
}
function Invoke-GuInventoryProbe([scriptblock]$Query,[int]$Limit) {
 try{
  $rows=@(& $Query)
  $kept=@()
  for($i=0;$i -lt [Math]::Min($rows.Count,$Limit);$i++){$kept+=,$rows[$i]}
  return [pscustomobject]@{
   Rows=$kept
   Status=[ordered]@{ReadStatus=$(if($rows.Count -gt $Limit){'partial'}else{'observed'});ObservedCount=$rows.Count;Truncated=($rows.Count -gt $Limit);InvalidRows=0}
  }
 }catch{
  # Provider messages, target objects and paths are intentionally not exported.
  return [pscustomobject]@{Rows=@();Status=[ordered]@{ReadStatus='unavailable';ObservedCount=0;Truncated=$false;InvalidRows=0}}
 }
}
function Test-GuInventoryIdentity($Value) {
 return ($Value -is [string] -and $Value.Length -le 2048 -and
  $Value -match '^[A-Za-z][A-Za-z0-9_-]{0,31}\\' -and $Value -notmatch '[\x00-\x1f\x7f]')
}
function ConvertTo-GuInventoryArchitecture($Value) {
 if($Value -isnot [string]){return 'unknown'}
 switch($Value.ToUpperInvariant()){
  'AMD64' {return 'x64'}
  'X64' {return 'x64'}
  'X86' {return 'x86'}
  'ARM64' {return 'arm64'}
  'ARM' {return 'arm'}
  'IA64' {return 'ia64'}
  default {return 'unknown'}
 }
}
function ConvertTo-GuInventoryHardware($Rows,[string[]]$Fields,$Status) {
 $out=@()
 foreach($row in $Rows){
  $item=[ordered]@{}
  try{
   foreach($field in $Fields){$item[$field]=Public-DriverLabel $row.$field}
   $out += [pscustomobject]$item
  }catch{$Status.ReadStatus='partial';$Status.InvalidRows++}
 }
 return $out
}
function Get-GuDiagnosticInventory {
 [CmdletBinding()]
 param([Collections.IDictionary]$Queries)
 # Tests supply every provider explicitly, so missing mocks never query the host.
 $required=@('Board','Bios','Cpu','OperatingSystem','Video','Drivers','PnpDisplay',
  'ReadParent','SecureBoot','Encryption','Elevated','Architecture','Firmware','Capabilities')
 if($null -eq $Queries){$Queries=Get-GuDiagnosticQueries}
 $effective=@{}
 foreach($name in $required){
  if($Queries.Contains($name) -and $Queries[$name] -is [scriptblock]){$effective[$name]=$Queries[$name]}
  else{$effective[$name]={throw 'Provider unavailable.'}}
 }
 $probes=[ordered]@{};$raw=@{}
 foreach($name in @('Board','Bios','Cpu','OperatingSystem','Video','Drivers','PnpDisplay','Elevated','Architecture','Firmware','Capabilities')){
  $limit=if($name -ceq 'Drivers'){512}elseif($name -cin @('Video','PnpDisplay')){64}elseif($name -cin @('Board','Bios','Cpu','OperatingSystem')){16}else{1}
  $raw[$name]=Invoke-GuInventoryProbe $effective[$name] $limit
  $probes[$name]=$raw[$name].Status
 }
 $hardware=[ordered]@{
  Board=@(ConvertTo-GuInventoryHardware $raw.Board.Rows @('Manufacturer','Product') $probes.Board)
  Bios=@(ConvertTo-GuInventoryHardware $raw.Bios.Rows @('Manufacturer','SMBIOSBIOSVersion') $probes.Bios)
  Cpu=@(ConvertTo-GuInventoryHardware $raw.Cpu.Rows @('Name','Manufacturer') $probes.Cpu)
  OperatingSystem=@(ConvertTo-GuInventoryHardware $raw.OperatingSystem.Rows @('Caption','Version','BuildNumber','OSArchitecture') $probes.OperatingSystem)
 }
 $elevated=$null
 if($raw.Elevated.Rows.Count -eq 1 -and $raw.Elevated.Rows[0] -is [bool]){$elevated=$raw.Elevated.Rows[0]}
 elseif($probes.Elevated.ReadStatus -ceq 'observed'){$probes.Elevated.ReadStatus='invalid'}
 $processArch='unknown';$nativeArch='unknown'
 if($raw.Architecture.Rows.Count -eq 1){
  $processArch=ConvertTo-GuInventoryArchitecture $raw.Architecture.Rows[0].Process
  $nativeArch=ConvertTo-GuInventoryArchitecture $raw.Architecture.Rows[0].Native
 }
 if($processArch -ceq 'unknown' -or $nativeArch -ceq 'unknown'){
  if($probes.Architecture.ReadStatus -ceq 'observed'){$probes.Architecture.ReadStatus='invalid'}
 }
 $firmware='unknown'
 if($raw.Firmware.Rows.Count -eq 1 -and $raw.Firmware.Rows[0] -is [string]){
  if($raw.Firmware.Rows[0] -ieq 'UEFI'){$firmware='UEFI'}
  elseif($raw.Firmware.Rows[0] -ieq 'BIOS'){$firmware='BIOS'}
 }
 if($firmware -ceq 'unknown' -and $probes.Firmware.ReadStatus -ceq 'observed'){$probes.Firmware.ReadStatus='invalid'}
 $capabilities=[ordered]@{}
 foreach($name in @('Get-CimInstance','Get-PnpDevice','Get-PnpDeviceProperty','Confirm-SecureBootUEFI','Get-Partition','Get-Disk','Get-Volume')){
  $value=$null
  if($raw.Capabilities.Rows.Count -eq 1 -and $raw.Capabilities.Rows[0].$name -is [bool]){$value=$raw.Capabilities.Rows[0].$name}
  elseif($probes.Capabilities.ReadStatus -ceq 'observed'){$probes.Capabilities.ReadStatus='invalid'}
  $capabilities[$name]=$value
 }
 # Merge matching CIM and PnP records by their private Windows identity. Keep
 # duplicate records from either provider and every distinct same-model device.
 $adapters=@();$identities=@{}
 foreach($v in $raw.Video.Rows){
  try{
   $id=if(Test-GuInventoryIdentity $v.PNPDeviceID){$v.PNPDeviceID}else{$null}
   if(!$id){$probes.Video.ReadStatus='partial';$probes.Video.InvalidRows++}
   $row=[pscustomobject]@{PNPDeviceID=$id;Name=(Public-DriverLabel $v.Name);Sources=@('CIM')}
   $adapters+=,$row
   if($id){
    if(!$identities.ContainsKey($id)){$identities[$id]=@()}
    $identities[$id]+=($adapters.Count-1)
   }
  }catch{$probes.Video.ReadStatus='partial';$probes.Video.InvalidRows++}
 }
 $pnpSeen=@{}
 foreach($v in $raw.PnpDisplay.Rows){
  try{
   $id=if(Test-GuInventoryIdentity $v.InstanceId){$v.InstanceId}else{$null}
   if(!$id){$probes.PnpDisplay.ReadStatus='partial';$probes.PnpDisplay.InvalidRows++}
   $ordinal=0
   if($id){
    if($pnpSeen.ContainsKey($id)){$ordinal=$pnpSeen[$id]}
    $pnpSeen[$id]=$ordinal+1
   }
   if($id -and $identities.ContainsKey($id) -and $ordinal -lt $identities[$id].Count){
    $row=$adapters[$identities[$id][$ordinal]]
    $row.Sources=@($row.Sources)+@('PnP')
    if(!$row.Name){$row.Name=Public-DriverLabel $v.FriendlyName}
   }else{
    $adapters+=,[pscustomobject]@{PNPDeviceID=$id;Name=(Public-DriverLabel $v.FriendlyName);Sources=@('PnP')}
   }
  }catch{$probes.PnpDisplay.ReadStatus='partial';$probes.PnpDisplay.InvalidRows++}
 }
 $adapterCount=$adapters.Count
 $truncated=$adapterCount -gt 64 -or $probes.Video.Truncated -or $probes.PnpDisplay.Truncated
 if($adapters.Count -gt 64){$adapters=@($adapters[0..63])}
 $drivers=@()
 foreach($d in $raw.Drivers.Rows){
  try{
   if(!(Test-GuInventoryIdentity $d.DeviceID)){$probes.Drivers.ReadStatus='partial';$probes.Drivers.InvalidRows++;continue}
   $drivers+=,[pscustomobject]@{
    DeviceID=$d.DeviceID;DriverProviderName=(Public-DriverLabel $d.DriverProviderName)
    Manufacturer=(Public-DriverLabel $d.Manufacturer);DriverVersion=(Public-DriverLabel $d.DriverVersion)
    InfName=(Public-DriverLabel $d.InfName);IsSigned=($d.IsSigned -is [bool] -and $d.IsSigned)
   }
  }catch{$probes.Drivers.ReadStatus='partial';$probes.Drivers.InvalidRows++}
 }
 $preflight=Get-PreflightReport ($elevated -eq $true) $effective.SecureBoot $adapters $drivers '' '' $effective.Encryption
 $context=New-PciParentContext
 $parents=Get-DisplayParentReport $adapters $effective.ReadParent $context
 $public=@()
 for($i=0;$i -lt $adapters.Count;$i++){
  $row=$preflight.DisplayAdapters[$i]
  $row['NodeId']=$parents.Targets[$i].AdapterNodeId
  $row['Name']=$adapters[$i].Name
  $row['Sources']=@($adapters[$i].Sources)
  $public+=,[pscustomobject]$row
 }
 $probes.SecureBoot=[ordered]@{ReadStatus=$(if($preflight.SecureBoot.State -cin @('enabled','disabled')){'observed'}else{'unavailable'})}
 $probes.Encryption=[ordered]@{ReadStatus=$(if($preflight.SystemVolumeEncryption.ReadStatus -ceq 'observed'){'observed'}else{'unavailable'})}
 $probes.Parents=[ordered]@{ReadStatus=$(if($parents.ReadStatus -ceq 'complete'){'observed'}else{'partial'});ExpectedChains=$parents.ExpectedChains;CompletedChains=$parents.CompletedChains}
 $complete=!$truncated -and $adapters.Count -gt 0
 foreach($p in $probes.Values){if($p.ReadStatus -cne 'observed'){$complete=$false}}
 return [pscustomobject][ordered]@{
  SchemaVersion=1;Test='unified-windows-inventory-v1';RunId=$context.RunId
  ReadStatus=$(if($complete){'complete'}else{'partial'})
  Hardware=[pscustomobject]$hardware
  Host=[pscustomobject][ordered]@{
   Elevated=$elevated;ProcessArchitecture=$processArch;NativeArchitecture=$nativeArch
   FirmwareType=$firmware;PowerShellVersion=$PSVersionTable.PSVersion.ToString()
   Capabilities=[pscustomobject]$capabilities
  }
  SecureBoot=$preflight.SecureBoot;SystemVolumeEncryption=$preflight.SystemVolumeEncryption
  DisplayAdapters=$public;ParentObservations=[pscustomobject]$parents;Probes=[pscustomobject]$probes
  AdapterRowsObserved=$adapterCount;AdaptersTruncated=[bool]$truncated
  RawIdentitiesExported=$false;PrebootTopologyVerified=$false;PhysicalDisplayRouteVerified=$false
  hardware_tested=$false;write_eligible=$false
 }
}
