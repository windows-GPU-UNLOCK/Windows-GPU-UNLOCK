# Windows device-parent associations only; no routing, MUX or preboot proof.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'
function Get-PciSummary([string]$Id){
 if($Id -match '^PCI\\VEN_([0-9A-F]{4})&DEV_([0-9A-F]{4})&SUBSYS_([0-9A-F]{8})(?:&|\\|$)'){
  return [ordered]@{Vendor=$Matches[1];Device=$Matches[2];Subsystem=$Matches[3]}
 }
 return $null
}
function Resolve-MonitorParent([string]$Instance,$Adapters,[scriptblock]$ReadParent){
 $result=[ordered]@{State='unknown';ParentHops=0;AdapterPci=$null}
 if(!$Instance -or $Instance.Length -gt 2048 -or $Adapters.Count -gt 16){return $result}
 # WmiMonitorConnectionParams appends a numeric WMI instance index.
 if($Instance -notmatch '^(DISPLAY\\.+)_([0-9]+)$'){return $result}
 $current=$Matches[1];$seen=@{}
 for($hop=0;$hop -lt 16;$hop++){
  if($seen.ContainsKey($current)){$result.State='cycle';return $result}
  $seen[$current]=$true
  $matches=@($Adapters|Where-Object { $_.PNPDeviceID -and [string]$_.PNPDeviceID -ieq $current })
  if($matches.Count -gt 1){$result.State='ambiguous';return $result}
  if($matches.Count -eq 1){
   $result.State='associated';$result.AdapterPci=Get-PciSummary $current
   return $result
  }
  try{$parent=@(& $ReadParent $current)}catch{return $result}
  if($parent.Count -ne 1 -or $parent[0] -isnot [string] -or !$parent[0] -or $parent[0].Length -gt 2048){return $result}
  $current=$parent[0];$result.ParentHops++
 }
 $result.State='hop-limit';return $result
}
function Get-MonitorAssociations($Monitors,$Adapters,[scriptblock]$ReadParent){
 if($Monitors.Count -gt 32 -or $Adapters.Count -gt 16){throw 'Inventory exceeds diagnostic bounds.'}
 $rows=@();$index=0
 foreach($m in $Monitors){
  $active=$null;if($m.Active -is [bool]){$active=$m.Active}
  $tech=$null
  if(($m.VideoOutputTechnology -is [uint32] -or $m.VideoOutputTechnology -is [int] -or $m.VideoOutputTechnology -is [long]) -and $m.VideoOutputTechnology -ge 0 -and $m.VideoOutputTechnology -le [uint32]::MaxValue){$tech=[long]$m.VideoOutputTechnology}
  $rows += [pscustomobject]@{Index=$index;Active=$active;VideoOutputTechnology=$tech;DeviceParent=(Resolve-MonitorParent ([string]$m.InstanceName) $Adapters $ReadParent)}
  $index++
 }
 return $rows
}
if($SelfTest){
 $pci='PCI\VEN_10DE&DEV_28A1&SUBSYS_13B91462\PRIVATE'
 $ad=@([pscustomobject]@{PNPDeviceID=$pci})
 $monitor=[pscustomobject]@{InstanceName='DISPLAY\PRIVATE\SERIAL_0';Active=$true;VideoOutputTechnology=[uint32]5}
 $reader={param($id) if($id -eq 'DISPLAY\PRIVATE\SERIAL'){return 'BRIDGE\PRIVATE'};if($id -eq 'BRIDGE\PRIVATE'){return $pci}}
 $r=@(Get-MonitorAssociations @($monitor) $ad $reader)
 if($r.Count -ne 1 -or $r[0].DeviceParent.State -cne 'associated' -or $r[0].DeviceParent.ParentHops -ne 2 -or $r[0].DeviceParent.AdapterPci.Device -cne '28A1'){throw 'Association regression.'}
 if(($r|ConvertTo-Json -Depth 8) -match 'PRIVATE|SERIAL|DISPLAY|BRIDGE'){throw 'Private identity leaked.'}
 if((Resolve-MonitorParent $monitor.InstanceName $ad {throw 'PRIVATE-ERROR'}).State -cne 'unknown'){throw 'Failed read became known.'}
 if((Resolve-MonitorParent $monitor.InstanceName $ad {param($id) $id}).State -cne 'cycle'){throw 'Cycle not bounded.'}
 if((Resolve-MonitorParent $monitor.InstanceName @($ad[0],$ad[0]) {param($id) $pci}).State -cne 'ambiguous'){throw 'Duplicate adapter accepted.'}
 if((Resolve-MonitorParent 'DISPLAY\PRIVATE\SERIAL' $ad $reader).State -cne 'unknown'){throw 'Malformed WMI suffix accepted.'}
 if((Resolve-MonitorParent $monitor.InstanceName $ad { 'A';'B' }).State -cne 'unknown'){throw 'Multiple parents accepted.'}
 $script:sequence=0
 if((Resolve-MonitorParent $monitor.InstanceName $ad {param($id) $script:sequence++;'NODE\'+$script:sequence}).State -cne 'hop-limit'){throw 'Hop limit failed.'}
 $refused=$false;try{Get-MonitorAssociations (@($monitor)*33) $ad $reader}catch{$refused=$true}
 if(!$refused){throw 'Monitor bound failed.'}
 $r=@(Get-MonitorAssociations @([pscustomobject]@{InstanceName=$null;Active='PRIVATE';VideoOutputTechnology='PRIVATE'}) $ad $reader)
 if($null -ne $r[0].Active -or $null -ne $r[0].VideoOutputTechnology){throw 'Invalid scalar exported.'}
 Write-Host 'PASS: association, redaction, failed/multiple parent, cycle, ambiguity, suffix and bounds.';exit
}
$status='observed';$rows=@()
try{
 $monitors=@(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop)
 $adapters=@(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
 $rows=@(Get-MonitorAssociations $monitors $adapters {
  param($id)
  $p=Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_Parent -ErrorAction Stop
  if($p.Type -cne 'String'){throw 'Unknown parent type.'}
  $p.Data
 })
}catch{$status='unavailable';$rows=@()}
$report=[ordered]@{Test='windows-monitor-parent-v1';ReadStatus=$status;Monitors=$rows;RawIdentitiesExported=$false;DisplayRoutingVerified=$false;PrebootOwnershipVerified=$false;HardwareUnlockTested=$false;WriteEligible=$false}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$folder=Join-Path $docs ('GPU-Unlock-Monitor-Parents-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $folder|Out-Null
$path=Join-Path $folder 'monitor-parents.json';$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only reviewed '+$path+'. Keep settings unchanged; no EFI or reboot.')
