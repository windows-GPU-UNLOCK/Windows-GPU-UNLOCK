# Pure configuration/inventory mocks; no hardware or disk staging.
[CmdletBinding()]
param([switch]$Report,[ValidateSet('42','151','196','200')][string]$Case='151')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-graph.ps1')
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(!$failed){throw 'Expected refusal.'}}
foreach($file in Get-ChildItem (Join-Path $PSScriptRoot 'graph-configurations') -Filter '*.json') {
 $p=Read-GraphConfiguration $file.BaseName
 $board=[pscustomobject]@{Manufacturer=$p.ManufacturerPrefix;Product=$p.Board}
 $bios=[pscustomobject]@{SMBIOSBIOSVersion=$p.Bios};$cpu=[pscustomobject]@{Name=$p.CpuToken}
 $video=@($p.Adapters|ForEach-Object{[pscustomobject]@{PNPDeviceID=('PCI\VEN_'+$_.Vendor+'&DEV_'+$_.Device+'&SUBSYS_'+$_.Subsystem+'\PRIVATE')}})
 $drivers=@()
 foreach($a in @($p.KnownNonPciAdapters | Where-Object {$_})){
  $id=$a.Enumerator+'\PRIVATE';$video += [pscustomobject]@{PNPDeviceID=$id}
  $drivers += [pscustomobject]@{DeviceID=$id;DriverProviderName=$a.Provider;DriverVersion=$a.Version;IsSigned=$true}
 }
 Assert-GraphMachine $p.Id $board $bios $cpu $video $drivers
 $oldManufacturer=$board.Manufacturer;$board.Manufacturer='OTHER';Reject {Assert-GraphMachine $p.Id $board $bios $cpu $video $drivers};$board.Manufacturer=$oldManufacturer
 $oldBoard=$board.Product;$board.Product+='other';Reject {Assert-GraphMachine $p.Id $board $bios $cpu $video $drivers};$board.Product=$oldBoard
 $oldCpu=$cpu.Name;$cpu.Name='OTHER';Reject {Assert-GraphMachine $p.Id $board $bios $cpu $video $drivers};$cpu.Name=$oldCpu
 Reject {Assert-GraphMachine $p.Id $board $bios $cpu @() $drivers}
 $bios.SMBIOSBIOSVersion+='other';Reject {Assert-GraphMachine $p.Id $board $bios $cpu $video $drivers};$bios.SMBIOSBIOSVersion=$p.Bios
 Reject {Assert-GraphMachine $p.Id $board $bios $cpu @($video+$video) $drivers}
 Reject {Assert-GraphMachine $p.Id $board $bios $cpu @($video+[pscustomobject]@{PNPDeviceID='USB\PRIVATE'}) $drivers}
 # Marketing name/version and even a signed driver cannot supply an unknown
 # firmware identity. Replay the reported Parsec case as untrusted metadata.
 if($p.Id -ceq 'issue92'){
  foreach($id in @($null,'ROOT\PRIVATE','SWD\PRIVATE')){
   $parsec=[pscustomobject]@{Name='Parsec Virtual Display Adapter';PNPDeviceID=$id}
   $parsecDriver=[pscustomobject]@{DeviceID=$id;DriverProviderName='Parsec';DriverVersion='0.45.0.0';IsSigned=$true}
   Reject {Assert-GraphMachine $p.Id $board $bios $cpu @($video+$parsec) @($parsecDriver)}
  }
 }
}
Reject {Read-GraphConfiguration '../issue33'}
Reject {Read-GraphConfiguration 'missing'}
# Issue151: preserve both physical GPUs and refuse every unknown software
# adapter independently, even when its marketing name/version are known.
$case151=Read-GraphConfiguration 'issue151'
$board151=[pscustomobject]@{Manufacturer='Gigabyte Technology Co., Ltd.';Product=$case151.Board}
$bios151=[pscustomobject]@{SMBIOSBIOSVersion='F40'}
$cpu151=[pscustomobject]@{Name='AMD Ryzen 7 5800X 8-Core Processor'}
$pci151=@($case151.Adapters|ForEach-Object{[pscustomobject]@{PNPDeviceID=('PCI\VEN_'+$_.Vendor+'&DEV_'+$_.Device+'&SUBSYS_'+$_.Subsystem+'\PRIVATE')}})
Assert-GraphMachine 'issue151' $board151 $bios151 $cpu151 $pci151
foreach($name in @('Virtual Desktop Monitor','SudoMaker Virtual Display Adapter','Meta Virtual Monitor','vorpX Virtual Display')){
 $unknown=[pscustomobject]@{Name=$name;PNPDeviceID=$null}
 Reject {Assert-GraphMachine 'issue151' $board151 $bios151 $cpu151 @($pci151+$unknown)}
}
foreach($enumerator in @('ROOT','SWD')){
 $unknown=[pscustomobject]@{PNPDeviceID=($enumerator+'\PRIVATE')}
 Reject {Assert-GraphMachine 'issue151' $board151 $bios151 $cpu151 @($pci151+$unknown)}
}
Reject {Assert-GraphMachine 'issue151' $board151 $bios151 $cpu151 @($pci151[0])}
$wrong151=@($pci151|ForEach-Object{[pscustomobject]@{PNPDeviceID=$_.PNPDeviceID.Replace('403F1458','48973842')}})
Reject {Assert-GraphMachine 'issue151' $board151 $bios151 $cpu151 $wrong151}
# New dual-NVIDIA case: an unconnected second NVIDIA adapter is still pinned.
# Disabled Windows display state must not be converted into a firmware claim.
$case196=Read-GraphConfiguration 'issue196'
$board196=[pscustomobject]@{Manufacturer='Micro-Star International Co., Ltd.';Product=$case196.Board}
$bios196=[pscustomobject]@{SMBIOSBIOSVersion=$case196.Bios}
$cpu196=[pscustomobject]@{Name='AMD Ryzen 7 9800X3D 8-Core Processor'}
$pci196=@($case196.Adapters|ForEach-Object{[pscustomobject]@{PNPDeviceID=('PCI\VEN_'+$_.Vendor+'&DEV_'+$_.Device+'&SUBSYS_'+$_.Subsystem+'\PRIVATE')}})
Assert-GraphMachine 'issue196' $board196 $bios196 $cpu196 $pci196
for($omit=0;$omit -lt $pci196.Count;$omit++){
 $remaining=@(for($at=0;$at -lt $pci196.Count;$at++){if($at -ne $omit){$pci196[$at]}})
 Reject {Assert-GraphMachine 'issue196' $board196 $bios196 $cpu196 $remaining}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('graph-config-'+[guid]::NewGuid().ToString('N'))
$case42=Read-GraphConfiguration 'issue42'
$board42=[pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Product=$case42.Board}
$bios42=[pscustomobject]@{SMBIOSBIOSVersion='4505'};$cpu42=[pscustomobject]@{Name='Intel Core i9-14900K'}
$pci42=@($case42.Adapters|ForEach-Object{[pscustomobject]@{PNPDeviceID=('PCI\VEN_'+$_.Vendor+'&DEV_'+$_.Device+'&SUBSYS_'+$_.Subsystem+'\PRIVATE')}})
Assert-GraphMachine 'issue42' $board42 $bios42 $cpu42 @($pci42[2],$pci42[1],$pci42[0])
for($omit=0;$omit -lt $pci42.Count;$omit++){
 $remaining=@(for($at=0;$at -lt $pci42.Count;$at++){if($at -ne $omit){$pci42[$at]}})
 Reject {Assert-GraphMachine 'issue42' $board42 $bios42 $cpu42 $remaining}
}
foreach($id in @($null,'ROOT\PRIVATE','SWD\PRIVATE')){
 $remote=[pscustomobject]@{Name='Microsoft Remote Display Adapter';PNPDeviceID=$id}
 $rd=[pscustomobject]@{DeviceID=$id;DriverProviderName='Microsoft';DriverVersion='test';IsSigned=$true}
 Reject {Assert-GraphMachine 'issue42' $board42 $bios42 $cpu42 @($pci42+$remote) @($rd)}
}
# Issue200's Meta name/version cannot identify a firmware adapter. Even signed
# ROOT/SWD metadata stays unknown; another card's board/subsystem cannot match.
$case200=Read-GraphConfiguration 'issue200'
$board200=[pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Product=$case200.Board}
$bios200=[pscustomobject]@{SMBIOSBIOSVersion='3636'}
$cpu200=[pscustomobject]@{Name='AMD Ryzen 7 5800X3D 8-Core Processor'}
$pci200=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2216&SUBSYS_48973842\PRIVATE'}
Assert-GraphMachine 'issue200' $board200 $bios200 $cpu200 @($pci200)
foreach($id in @($null,'ROOT\PRIVATE','SWD\PRIVATE')){
 $meta=[pscustomobject]@{Name='Meta Virtual Monitor';DriverVersion='5.3.57.114';PNPDeviceID=$id}
 $signed=[pscustomobject]@{DeviceID=$id;DriverProviderName='Meta';DriverVersion='5.3.57.114';IsSigned=$true}
 Reject {Assert-GraphMachine 'issue200' $board200 $bios200 $cpu200 @($pci200,$meta) @($signed)}
}
$bios200.SMBIOSBIOSVersion='3621';Reject {Assert-GraphMachine 'issue200' $board200 $bios200 $cpu200 @($pci200)};$bios200.SMBIOSBIOSVersion='3636'
$other200=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2216&SUBSYS_403F1458\PRIVATE'}
Reject {Assert-GraphMachine 'issue200' $board200 $bios200 $cpu200 @($other200)}
New-Item -ItemType Directory -Path $temp|Out-Null
$good=Get-Content (Join-Path $PSScriptRoot 'graph-configurations/issue33.json') -Raw
foreach($bad in @(
 $good.Replace('graph-only','unlock'),
 $good.Replace('"SchemaVersion": 1','"SchemaVersion": 2'),
 $good.Replace('"2204"','".*"'),
 $good.Replace('"Board":','"Unexpected": 1, "Board":'),
 $good.Replace('"Adapters": [','"Adapters": null, "extra": ['),
 $good.Replace('"Id": "issue33"','"Id": "other"')
)) {
 [IO.File]::WriteAllText((Join-Path $temp 'issue33.json'),$bad)
 Reject {Read-GraphConfiguration 'issue33' $temp}
}
$known=Get-Content (Join-Path $PSScriptRoot 'graph-configurations/issue31.json') -Raw
foreach($bad in @($known.Replace('"LCI"','"PCI"'),$known.Replace('"LuminonCore"','".*"'),$known.Replace('"1.0.2018.1204"','"*"'))){
 [IO.File]::WriteAllText((Join-Path $temp 'issue31.json'),$bad)
 Reject {Read-GraphConfiguration 'issue31' $temp}
}
# Legacy dot-source entry point must expose functions without executing a run.
. (Join-Path $PSScriptRoot 'prepare-x99-graph.ps1')
if((Read-GraphConfiguration 'issue33').Scope -cne 'graph-only'){throw 'Legacy entry point failed'}
Write-Host 'PASS: all configuration fixtures, mismatched BIOS/adapters, unknown inventory, traversal, malformed schema/scope/IDs, legacy entry point.'
if($Report){
 $docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents unavailable.'}
 $folder=Join-Path $docs ('GPU-Unlock-Graph-Config-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 New-Item -ItemType Directory -Path $folder|Out-Null
 $summary=[ordered]@{Test='graph-configuration-v2';Passed=$true;Case='151';FixtureOnly=$true;PhysicalAdapterPins=2;UnknownDisplayCasesRefused=6;MissingDisplayRefused=$true;Other2216SubsystemRefused=$true;HardwareInventoryRead=$false;HardwareUnlockTested=$false;VirtualAdapterAdmissionGranted=$false;WriteEligible=$false}
 if($Case -ceq '196'){$summary=[ordered]@{Test='graph-configuration-v3';Passed=$true;Case='196';FixtureOnly=$true;PhysicalAdapterPins=3;MissingPhysicalAdapterCasesRefused=3;A4000Required=$true;DisabledIgpuProvesPrebootGop=$false;HardwareInventoryRead=$false;HardwareUnlockTested=$false;VirtualAdapterAdmissionGranted=$false;WriteEligible=$false}}
 if($Case -ceq '200'){$summary=[ordered]@{Test='graph-configuration-v4';Passed=$true;Case='200';FixtureOnly=$true;PhysicalAdapterPins=1;UnknownMetaCasesRefused=3;OtherBiosRefused=$true;OtherSubsystemRefused=$true;HardwareInventoryRead=$false;HardwareUnlockTested=$false;VirtualAdapterAdmissionGranted=$false;WriteEligible=$false}}
 if($Case -ceq '42'){$summary=[ordered]@{Test='graph-configuration-v5';Passed=$true;Case='42';FixtureOnly=$true;PhysicalAdapterPins=3;NvidiaCandidates=2;MissingAdapterCasesRefused=3;UnknownRemoteCasesRefused=3;AdapterOrderIndependent=$true;IndexBasedTargetSelectionAuthorized=$false;UnlockSequenceEstablished=$false;HardwareInventoryRead=$false;HardwareUnlockTested=$false;VirtualAdapterAdmissionGranted=$false;WriteEligible=$false}}
 $path=Join-Path $folder 'graph-configuration.json'
 $summary|ConvertTo-Json|Set-Content -LiteralPath $path -Encoding UTF8
 Write-Host ('Return only '+$path+'. This tests fixtures, not your hardware. No EFI, settings changes or reboot.')
}
