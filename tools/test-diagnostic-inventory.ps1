# GPL-2.0-only. RAM-only tests of the real unified Windows inventory functions.
$ErrorActionPreference='Stop'
$script:liveQueries=0;$script:reportWrites=0;$script:checks=0
function Get-CimInstance {$script:liveQueries++;throw 'Unexpected live CIM query'}
function Get-PnpDevice {$script:liveQueries++;throw 'Unexpected live PnP query'}
function Get-PnpDeviceProperty {$script:liveQueries++;throw 'Unexpected live parent query'}
function Get-ComputerInfo {$script:liveQueries++;throw 'Unexpected live firmware query'}
function Confirm-SecureBootUEFI {$script:liveQueries++;throw 'Unexpected live Secure Boot query'}
function New-Item {$script:reportWrites++;throw 'Inventory must not create a report folder'}
$Python='KEEP-PYTHON';$SessionRoot='KEEP-SESSION';$Offline='KEEP-OFFLINE';$Drive='KEEP-DRIVE'
$SelfTest='KEEP-SELFTEST';$Case='KEEP-CASE';$ExpectedDevice='KEEP-DEVICE';$ExpectedSubsystem='KEEP-SUBSYSTEM'
. (Join-Path $PSScriptRoot 'diagnostic-inventory.ps1')
function Check([bool]$Condition,[string]$Label){
 $script:checks++
 if(!$Condition){throw ('Diagnostic inventory regression: '+$Label)}
}
Check ($script:liveQueries -eq 0 -and $script:reportWrites -eq 0) 'imports only define helpers'
Check ($Python -ceq 'KEEP-PYTHON' -and $SessionRoot -ceq 'KEEP-SESSION' -and $Offline -ceq 'KEEP-OFFLINE' -and $Drive -ceq 'KEEP-DRIVE') 'import preserves launcher parameters'
Check ($SelfTest -ceq 'KEEP-SELFTEST' -and $Case -ceq 'KEEP-CASE' -and $ExpectedDevice -ceq 'KEEP-DEVICE' -and $ExpectedSubsystem -ceq 'KEEP-SUBSYSTEM') 'legacy parameter aliases do not clobber caller variables'
$script:a='PCI\VEN_10DE&DEV_2204&SUBSYS_145410DE\PRIVATE-A'
$script:b='PCI\VEN_10DE&DEV_2204&SUBSYS_145410DE\PRIVATE-B'
$script:i='PCI\VEN_8086&DEV_A780&SUBSYS_7E131462\PRIVATE-I'
$script:v='ROOT\DISPLAY\PRIVATE-V'
$script:x='PCI\VEN_1002&DEV_164E&SUBSYS_88771043\PRIVATE-X'
$script:bridgeA='PCI\VEN_1022&DEV_43F5\PRIVATE-BRIDGE-A'
$script:bridgeB='PCI\VEN_1022&DEV_43F5\PRIVATE-BRIDGE-B'
$script:shared='PCI\VEN_1022&DEV_14DB\PRIVATE-SHARED'
function New-TestQueries {
 return @{
  Board={[pscustomobject]@{Manufacturer='Example Board';Product='Board 1';SerialNumber='PRIVATE'}}
  Bios={[pscustomobject]@{Manufacturer='Example BIOS';SMBIOSBIOSVersion='1.0';SerialNumber='PRIVATE'}}
  Cpu={[pscustomobject]@{Name='Example CPU';Manufacturer='Example';ProcessorId='PRIVATE'}}
  OperatingSystem={[pscustomobject]@{Caption='Windows Test';Version='10.0';BuildNumber='12345';OSArchitecture='64-bit';CSName='PRIVATE';SerialNumber='PRIVATE'}}
  Video={
   [pscustomobject]@{PNPDeviceID=$script:a;Name='NVIDIA GPU A'}
   [pscustomobject]@{PNPDeviceID=$script:b;Name='NVIDIA GPU B'}
   [pscustomobject]@{PNPDeviceID=$script:i;Name='Intel Graphics'}
   [pscustomobject]@{PNPDeviceID=$script:v;Name='Virtual Display'}
  }
  Drivers={
   foreach($id in @($script:a,$script:b,$script:i,$script:v,$script:x)){
    [pscustomobject]@{DeviceID=$id;DriverProviderName='Example Provider';Manufacturer='Example';DriverVersion='1.2.3';InfName='oem1.inf';IsSigned=$true;PrivatePath='C:\PRIVATE'}
   }
  }
  PnpDisplay={
   foreach($id in @($script:a,$script:b,$script:i,$script:v,$script:x)){
    [pscustomobject]@{InstanceId=$id;FriendlyName='PnP display';PrivatePath='C:\PRIVATE'}
   }
  }
  ReadParent={
   param($id)
   if($id -ieq $script:a){$script:bridgeA}
   elseif($id -ieq $script:b){$script:bridgeB}
   elseif($id -ieq $script:bridgeA -or $id -ieq $script:bridgeB -or $id -ieq $script:i -or $id -ieq $script:x){$script:shared}
   else{'HTREE\ROOT\0'}
  }
  SecureBoot={$false}
  Encryption={[pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage=0;FullyDecryptedObserved=$true;RecoveryPassword='PRIVATE'}}
  Elevated={$false}
  Architecture={[pscustomobject]@{Process='AMD64';Native='AMD64';ComputerName='PRIVATE'}}
  Firmware={'UEFI'}
  Capabilities={
   $r=[ordered]@{}
   foreach($name in @('Get-CimInstance','Get-PnpDevice','Get-PnpDeviceProperty','Confirm-SecureBootUEFI','Get-Partition','Get-Disk','Get-Volume')){$r[$name]=$true}
   [pscustomobject]$r
  }
 }
}
function Check-Public($Report){
 $text=$Report|ConvertTo-Json -Depth 20
 Check ($text -notmatch 'PRIVATE|PNPDeviceID|InstanceId|SerialNumber|ProcessorId|RecoveryPassword|ComputerName|PrivatePath|PCI\\\\|HTREE') 'public report omits identities, secrets and paths'
 Check ($Report.hardware_tested -ceq $false -and $Report.write_eligible -ceq $false) 'no observation grants unlock eligibility'
 Check ($Report.RawIdentitiesExported -ceq $false -and $Report.PrebootTopologyVerified -ceq $false -and $Report.PhysicalDisplayRouteVerified -ceq $false) 'Windows observations remain distinct from firmware and connectors'
 Check ($Report.RunId -ceq $Report.ParentObservations.RunId) 'single run context'
}
$q=New-TestQueries
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.ReadStatus -ceq 'complete' -and $r.DisplayAdapters.Count -eq 5) 'all independent providers complete'
Check ($r.DisplayAdapters[0].Sources.Count -eq 2 -and $r.DisplayAdapters[4].Sources[0] -ceq 'PnP') 'CIM and PnP merge without losing PnP-only adapter'
Check ($r.DisplayAdapters[0].NodeId -cne $r.DisplayAdapters[1].NodeId) 'same model and subsystem remain distinct adapters'
Check ($r.DisplayAdapters[0].Pci.Device -ceq '2204' -and $r.DisplayAdapters[3].Pci -eq $null) 'physical and virtual observations retained'
Check ($r.ParentObservations.Targets[0].Nodes[1].Pci.Device -ceq $r.ParentObservations.Targets[1].Nodes[1].Pci.Device -and $r.ParentObservations.Targets[0].Nodes[1].NodeId -cne $r.ParentObservations.Targets[1].Nodes[1].NodeId) 'same bridge model is not shared identity'
Check ($r.ParentObservations.Targets[0].Nodes[2].NodeId -ceq $r.ParentObservations.Targets[1].Nodes[2].NodeId) 'actual shared parent is represented once by opaque identity'
Check ($r.DisplayAdapters[0].NodeId -ceq $r.ParentObservations.Targets[0].AdapterNodeId) 'adapter links to its own bounded chain'
Check ($r.Host.Elevated -ceq $false -and $r.Host.NativeArchitecture -ceq 'x64' -and $r.Host.FirmwareType -ceq 'UEFI') 'host capability observations'
Check ($r.DisplayAdapters[0].MatchingDriverCount -eq 1 -and $r.DisplayAdapters[0].Drivers[0].Signed -ceq $true) 'driver metadata association'
Check-Public $r
$other=Get-GuDiagnosticInventory -Queries (New-TestQueries)
Check ($r.RunId -cne $other.RunId -and $r.DisplayAdapters[0].NodeId -cne $other.DisplayAdapters[0].NodeId) 'node identities cannot correlate separate runs'

$q=New-TestQueries
$q.Video={throw 'C:\PRIVATE CIM unavailable'}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.ReadStatus -ceq 'partial' -and $r.Probes.Video.ReadStatus -ceq 'unavailable' -and $r.DisplayAdapters.Count -eq 5) 'PnP rows survive unavailable CIM'
Check-Public $r

$q=New-TestQueries
$q.PnpDisplay={throw 'C:\PRIVATE PnP unavailable'}
$q.ReadParent={throw 'PRIVATE parent provider missing'}
$q.SecureBoot={throw 'PRIVATE policy query denied'}
$q.Encryption={throw 'PRIVATE encryption provider denied'}
$q.Board={throw 'PRIVATE optional board query denied'}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.ReadStatus -ceq 'partial' -and $r.DisplayAdapters.Count -eq 4) 'CIM rows survive unavailable optional providers'
Check ($r.SecureBoot.State -ceq 'unknown' -and $r.SystemVolumeEncryption.ReadStatus -ceq 'unknown') 'unknown policy is not disabled or decrypted'
Check ($r.ParentObservations.CompletedChains -eq 0 -and $r.ParentObservations.Targets[0].Nodes.Count -eq 1) 'partial parent query retains adapter observation'
Check ($r.Probes.PnpDisplay.ReadStatus -ceq 'unavailable' -and $r.Probes.Parents.ReadStatus -ceq 'partial') 'provider failures remain distinct'
Check-Public $r

$r=Get-GuDiagnosticInventory -Queries @{}
Check ($r.ReadStatus -ceq 'partial' -and $r.DisplayAdapters.Count -eq 0 -and $r.Host.Elevated -eq $null) 'no available provider still yields a useful report'
Check ($r.Probes.Video.ReadStatus -ceq 'unavailable' -and $r.Probes.Firmware.ReadStatus -ceq 'unavailable') 'missing injected providers never query live host'
Check-Public $r

$q=New-TestQueries
$q.Video={
 [pscustomobject]@{PNPDeviceID=$script:a;Name='GPU A'}
 [pscustomobject]@{PNPDeviceID=$script:a;Name='GPU A repeated'}
 [pscustomobject]@{PNPDeviceID=$script:b;Name='GPU B'}
}
$q.PnpDisplay={}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.DisplayAdapters.Count -eq 3 -and $r.ParentObservations.DuplicateIdentityCount -eq 1) 'duplicate source records are preserved'
Check ($r.DisplayAdapters[0].NodeId -ceq $r.DisplayAdapters[1].NodeId -and $r.DisplayAdapters[2].NodeId -cne $r.DisplayAdapters[0].NodeId) 'same raw identity and same model remain distinguishable concepts'
Check-Public $r

$q=New-TestQueries
$q.Video={
 [pscustomobject]@{PNPDeviceID=$null;Name='C:\PRIVATE\bad'}
 [pscustomobject]@{PNPDeviceID=('X'*2049);Name='Unknown Display'}
 [pscustomobject]@{PNPDeviceID=$script:a;Name='NVIDIA GPU'}
}
$q.PnpDisplay={}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.ReadStatus -ceq 'partial' -and $r.DisplayAdapters.Count -eq 3 -and $r.Probes.Video.InvalidRows -eq 2) 'malformed identity does not discard useful rows'
Check ($r.DisplayAdapters[0].Name -eq $null -and $r.DisplayAdapters[1].NodeId -cne $r.DisplayAdapters[0].NodeId) 'invalid identities retain separate opaque row references'
Check ($r.ParentObservations.Targets[0].State -ceq 'error' -and $r.ParentObservations.Targets[0].Nodes.Count -eq 0) 'invalid identity cannot drive parent lookup'
Check-Public $r

$q=New-TestQueries
$q.Video={1..70|ForEach-Object {[pscustomobject]@{PNPDeviceID=('PCI\VEN_10DE&DEV_2204&SUBSYS_145410DE\PRIVATE-'+$_);Name='NVIDIA GPU'}}}
$q.PnpDisplay={}
$q.ReadParent={''}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.ReadStatus -ceq 'partial' -and $r.AdaptersTruncated -and $r.DisplayAdapters.Count -eq 64 -and $r.Probes.Video.ObservedCount -eq 70) 'bounded inventory records truncation instead of claiming completeness'
Check-Public $r

$q=New-TestQueries
$q.Elevated={'false'}
$q.Architecture={[pscustomobject]@{Process='C:\PRIVATE';Native='PRIVATE'}}
$q.Firmware={'not-known'}
$q.Capabilities={[pscustomobject]@{'Get-CimInstance'='true'}}
$q.SecureBoot={'false'}
$q.Encryption={[pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage='0';FullyDecryptedObserved=$true}}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.Host.Elevated -eq $null -and $r.Host.NativeArchitecture -ceq 'unknown' -and $r.Host.FirmwareType -ceq 'unknown') 'false-like strings and unknown host types remain unknown'
Check ($r.Probes.Elevated.ReadStatus -ceq 'invalid' -and $r.Probes.Capabilities.ReadStatus -ceq 'invalid') 'invalid host observations are explicit'
Check (!$r.SystemVolumeEncryption.FullyDecryptedObserved -and $r.SecureBoot.State -ceq 'unknown') 'invalid policy types cannot qualify'
Check-Public $r

$q=New-TestQueries
$q.Encryption={[pscustomobject]@{ReadStatus='observed';ProtectionState='off';ConversionState='fully-decrypted';EncryptionPercentage=[long]0;FullyDecryptedObserved=$true}}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.SystemVolumeEncryption.FullyDecryptedObserved) 'exact Int64 encryption percentage supports PowerShell 7 JSON'
Check-Public $r

$q=New-TestQueries
$q.Drivers={[pscustomobject]@{DeviceID=$script:a;DriverProviderName='C:\PRIVATE';Manufacturer='Example';DriverVersion='1.2.3';InfName='C:\PRIVATE\driver.inf';IsSigned='true'}}
$r=Get-GuDiagnosticInventory -Queries $q
Check ($r.DisplayAdapters[0].Drivers[0].Signed -ceq $false -and $r.DisplayAdapters[0].Drivers[0].Provider -eq $null -and $r.DisplayAdapters[0].Drivers[0].Inf -eq $null) 'driver metadata cannot coerce signature truth or expose paths'
Check-Public $r

$report=Get-DisplayParentReport -Devices @([pscustomobject]@{InstanceId=$script:a},[pscustomobject]@{InstanceId=$script:b}) -ReadParent {''}
Check ($report.ReadStatus -ceq 'complete' -and $report.Targets.Count -eq 2) 'generic parent API needs no issue case'
Check ($report.Targets[0].AdapterNodeId -cne $report.Targets[1].AdapterNodeId) 'generic API preserves same-model devices'
Check ($script:liveQueries -eq 0 -and $script:reportWrites -eq 0) 'all tests are RAM-only with no output folders'
Write-Host ('PASS: '+$script:checks+' unified inventory assertions; native PowerShell '+$PSVersionTable.PSVersion+'. No live queries or output files.')
