# Mock identity/filesystem checks only; no real firmware or device queries.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-resource-capture.ps1')
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(!$failed){throw 'Expected refusal absent'}}
$p=Read-ProbeConfiguration 'issue31'
$b=[pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Product='PRIME X570-PRO'}
$bios=[pscustomobject]@{SMBIOSBIOSVersion='5013'};$cpu=[pscustomobject]@{Name='AMD Ryzen 9 5950X 16-Core Processor'}
$gpu=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_147D10DE&REV_A1\PRIVATE'}
$lci=[pscustomobject]@{PNPDeviceID='LCI\PRIVATE'};$root=[pscustomobject]@{PNPDeviceID='ROOT\PRIVATE'}
$driver=[pscustomobject]@{DeviceID='LCI\PRIVATE';DriverProviderName='LuminonCore';DriverVersion='1.0.2018.1204';IsSigned=$true}
Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci) @($driver)
Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci,$root) @($driver)}
$swd=[pscustomobject]@{PNPDeviceID='SWD\PRIVATE'}
Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci,$swd) @($driver)}
foreach($signed in @($false,$true)){
 $extra=[pscustomobject]@{DeviceID=$root.PNPDeviceID;DriverProviderName='Punktfunk';DriverVersion='9.9.929.102';IsSigned=$signed}
 Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci,$root) @($driver,$extra)}
}
Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci,$gpu) @($driver)}
Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu) @($driver)}
Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci) @()}
$driver.IsSigned=$false;Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci) @($driver)};$driver.IsSigned=$true
$driver.DriverVersion='other';Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci) @($driver)};$driver.DriverVersion='1.0.2018.1204'
$gpu.PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_000010DE\PRIVATE';Reject {Assert-PinnedProbe $p $b $bios $cpu @($gpu,$lci) @($driver)}
$lenovo=Read-ProbeConfiguration 'issue19'
$lb=[pscustomobject]@{Manufacturer='LENOVO';Product='1052'};$lbi=[pscustomobject]@{SMBIOSBIOSVersion='S0AKT48A'};$lc=[pscustomobject]@{Name='Intel Core i9-11900K'}
$lv=[pscustomobject]@{PNPDeviceID=('PCI'+[char]92+'VEN_10DE&DEV_2504&SUBSYS_881D1043'+[char]92+'PRIVATE')}
Assert-PinnedProbe $lenovo $lb $lbi $lc @($lv)
$lb.Manufacturer='LENOVO-other';Reject {Assert-PinnedProbe $lenovo $lb $lbi $lc @($lv)};$lb.Manufacturer='LENOVO'
$lb.Product='other';Reject {Assert-PinnedProbe $lenovo $lb $lbi $lc @($lv)};$lb.Product='1052'
Reject {Assert-PinnedProbe $lenovo $lb $lbi $lc @($lv,$lv)}
Reject {Read-ProbeConfiguration '../issue31'}
$zotac=Read-ProbeConfiguration 'issue114'
$zb=[pscustomobject]@{Manufacturer='Gigabyte Technology Co., Ltd.';Product='B650M DS3H'}
$zbi=[pscustomobject]@{SMBIOSBIOSVersion='F21'};$zc=[pscustomobject]@{Name='AMD Ryzen 5 7600'}
$zv=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA\PRIVATE'}
$amd=[pscustomobject]@{PNPDeviceID='PCI\VEN_1002&DEV_164E&SUBSYS_D0001458\PRIVATE'}
Assert-PinnedProbe $zotac $zb $zbi $zc @($zv,$amd)
foreach($wrong in @('PCI\VEN_1002&DEV_13C0&SUBSYS_D0001458\PRIVATE','PCI\VEN_1002&DEV_164E&SUBSYS_7D751462\PRIVATE')){
 Reject {Assert-PinnedProbe $zotac $zb $zbi $zc @($zv,[pscustomobject]@{PNPDeviceID=$wrong})}
}
Reject {Assert-PinnedProbe $zotac $zb $zbi $zc @($zv)}
Reject {Assert-PinnedProbe $zotac $zb $zbi $zc @($zv,$amd,$amd)}
$evga=Read-ProbeConfiguration 'issue173'
$eb=[pscustomobject]@{Manufacturer='Micro-Star International Co., Ltd.';Product='MEG Z790 ACE (MS-7D86)'}
$ebi=[pscustomobject]@{SMBIOSBIOSVersion='1.G0'};$ec=[pscustomobject]@{Name='Intel Core i9-13900K'}
$ev=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2216&SUBSYS_48973842\PRIVATE'}
$ei=[pscustomobject]@{PNPDeviceID='PCI\VEN_8086&DEV_A780&SUBSYS_7D861462\PRIVATE'}
Assert-PinnedProbe $evga $eb $ebi $ec @($ev,$ei)
foreach($wrong in @('PCI\VEN_10DE&DEV_2216&SUBSYS_403F1458\PRIVATE','PCI\VEN_10DE&DEV_2204&SUBSYS_48973842\PRIVATE')){
 Reject {Assert-PinnedProbe $evga $eb $ebi $ec @([pscustomobject]@{PNPDeviceID=$wrong},$ei)}
}
Reject {Assert-PinnedProbe $evga $eb $ebi $ec @($ev)}
$ebi.SMBIOSBIOSVersion='other';Reject {Assert-PinnedProbe $evga $eb $ebi $ec @($ev,$ei)}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('resource-prep-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$zraw=Get-Content (Join-Path $PSScriptRoot 'probe-configurations/issue114.json') -Raw
foreach($bad in @($zraw.Replace('"OtherPciDevice": "164E"','"OtherPciDevice": null'),$zraw.Replace('"OtherPciSubsystem": "D0001458"','"OtherPciSubsystem": "*"'))){
 [IO.File]::WriteAllText((Join-Path $temp 'issue114.json'),$bad);Reject {Read-ProbeConfiguration 'issue114' $temp}
}
$raw=Get-Content (Join-Path $PSScriptRoot 'probe-configurations/issue31.json') -Raw
foreach($bad in @($raw.Replace('"SchemaVersion": 2','"SchemaVersion": 1'),$raw.Replace('"OtherPciDevice": null','"OtherPciDevice": "164E"'),$raw.Replace('"TargetBus": 8','"TargetBus": 0'),$raw.Replace('pinned-read-only-resource-capture','unlock'),$raw.Replace('220410de','ffffffff'),$raw.Replace('"LCI"','"PCI"'))){
 [IO.File]::WriteAllText((Join-Path $temp 'issue31.json'),$bad);Reject {Read-ProbeConfiguration 'issue31' $temp}
}
$source=Join-Path $temp 'source.efi';[IO.File]::WriteAllText($source,'mock fixture')
Stage-Probe $temp $source (ProbeHash $source) 'issue31'
if(!(Test-Path -LiteralPath (Join-Path $temp 'RTX3090-UNLOCK/pinned-probe-stage.json'))){throw 'Generic stage receipt missing'}
Reject {Stage-Probe $temp $source (ProbeHash $source) 'issue31'}
Write-Host 'PASS: X570/3090/LCI pins, changed inventory/driver refusals, malformed configuration, generic stage marker and repeat refusal.'
