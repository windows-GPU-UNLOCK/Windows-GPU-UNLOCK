# Mock filesystem and inventory only; does not query or stage a real disk.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-graph.ps1')
function Reject([scriptblock]$Action){$rejected=$false;try {& $Action}catch {$rejected=$true};if(!$rejected){throw 'Expected refusal did not occur.'}}
$board=[pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Product='X99-PRO/USB 3.1'}
$bios=[pscustomobject]@{SMBIOSBIOSVersion='4101'};$cpu=[pscustomobject]@{Name='Intel Core i7-5820K'}
$video=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_87AF1043&REV_A1\PRIVATE'}
Assert-X99GraphMachine $board $bios $cpu $video
$bios.SMBIOSBIOSVersion='other';Reject {Assert-X99GraphMachine $board $bios $cpu $video};$bios.SMBIOSBIOSVersion='4101'
Reject {Assert-X99GraphMachine $board $bios $cpu @($video,$video)}
$gigabyte=[pscustomobject]@{Manufacturer='Gigabyte Technology Co., Ltd.';Product='B560M DS3H V2'}
$b560bios=[pscustomobject]@{SMBIOSBIOSVersion='F7 RB'};$i5=[pscustomobject]@{Name='Intel Core i5-11400F'}
$ga104=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2487&SUBSYS_40721458&REV_A1\PRIVATE'}
Assert-GraphMachine 'issue109' $gigabyte $b560bios $i5 $ga104
Reject {Assert-GraphMachine 'issue33' $gigabyte $b560bios $i5 $ga104}
Reject {Assert-GraphMachine 'issue109' $gigabyte $b560bios $i5 $video}
$x570=[pscustomobject]@{Manufacturer='ASUSTeK COMPUTER INC.';Product='PRIME X570-PRO'}
$x570bios=[pscustomobject]@{SMBIOSBIOSVersion='5013'};$ryzen=[pscustomobject]@{Name='AMD Ryzen 9 5950X 16-Core Processor'}
$nvidia=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_147D10DE&REV_A1\PRIVATE'}
$virtual=[pscustomobject]@{PNPDeviceID='ROOT\DISPLAY\PRIVATE'}
$lci=[pscustomobject]@{PNPDeviceID='LCI\PRIVATE'}
$lciDriver=[pscustomobject]@{DeviceID='LCI\PRIVATE';DriverProviderName='LuminonCore';DriverVersion='1.0.2018.1204';IsSigned=$true}
Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci) @($lciDriver)
Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$virtual,$lci) @($lciDriver)}
Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$virtual)}
Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci) @()}
Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci,$lci) @($lciDriver)}
$lciDriver.DriverProviderName='other';Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci) @($lciDriver)};$lciDriver.DriverProviderName='LuminonCore'
$lciDriver.DriverVersion='other';Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci) @($lciDriver)};$lciDriver.DriverVersion='1.0.2018.1204'
$lciDriver.IsSigned=$false;Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci) @($lciDriver)};$lciDriver.IsSigned=$true
$lciDriver.DeviceID='OTHER\PRIVATE';Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$lci) @($lciDriver)};$lciDriver.DeviceID='LCI\PRIVATE'

Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,$ga104)}
Reject {Assert-GraphMachine 'issue31' $x570 $x570bios $ryzen @($nvidia,[pscustomobject]@{PNPDeviceID=$null})}
$b550=[pscustomobject]@{Manufacturer='Gigabyte Technology Co., Ltd.';Product='B550 AORUS ELITE V2'}
$f19=[pscustomobject]@{SMBIOSBIOSVersion='F19'};$apu=[pscustomobject]@{Name='AMD Ryzen 5 5600G with Radeon Graphics'}
$rtxTi=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2489&SUBSYS_153C10DE&REV_A1\PRIVATE'}
$amd=[pscustomobject]@{PNPDeviceID='PCI\VEN_1002&DEV_1638&SUBSYS_D0001458&REV_C9\PRIVATE'}
Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$amd)
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$amd,$virtual)}
$swd=[pscustomobject]@{PNPDeviceID='SWD\DISPLAY\PRIVATE'}
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$amd,$swd)}
$punktfunk=[pscustomobject]@{DeviceID=$virtual.PNPDeviceID;DriverProviderName='Punktfunk';DriverVersion='9.9.929.102';IsSigned=$false}
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$amd,$virtual) @($punktfunk)}
$punktfunk.IsSigned=$true
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$amd,$virtual) @($punktfunk)}
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi)}
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$nvidia)}
Reject {Assert-GraphMachine 'issue180' $b550 $f19 $apu @($rtxTi,$amd,$nvidia)}
$lenovo=[pscustomobject]@{Manufacturer='LENOVO';Product='1052'}
$lenovoBios=[pscustomobject]@{SMBIOSBIOSVersion='S0AKT48A'};$i9=[pscustomobject]@{Name='11th Gen Intel Core i9-11900K'}
$ga106=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2504&SUBSYS_881D1043&REV_A1\PRIVATE'}
Assert-GraphMachine 'issue19' $lenovo $lenovoBios $i9 $ga106
Reject {Assert-GraphMachine 'issue19' $lenovo $lenovoBios $i9 $rtxTi}
Reject {Assert-GraphMachine 'issue19' $lenovo $lenovoBios $i9 @($ga106,$amd)}
$part=[pscustomobject]@{IsBoot=$false;IsSystem=$false}
$disk=[pscustomobject]@{BusType='USB';UniqueId='mock-usb';IsBoot=$false;IsSystem=$false;IsReadOnly=$false;IsOffline=$false}
$volume=[pscustomobject]@{FileSystem='FAT32';SizeRemaining=64MB}
Assert-GraphUsb $part $disk $volume
$disk.BusType='SATA';Reject {Assert-GraphUsb $part $disk $volume};$disk.BusType='USB'
$part.IsSystem=$true;Reject {Assert-GraphUsb $part $disk $volume};$part.IsSystem=$false
$volume.FileSystem='NTFS';Reject {Assert-GraphUsb $part $disk $volume}
$volume.FileSystem='FAT32';$volume.SizeRemaining=1MB;Reject {Assert-GraphUsb $part $disk $volume}
Assert-GraphUsb $part $disk $volume -CollectOnly
$disk.IsReadOnly=$true;Assert-GraphUsb $part $disk $volume -CollectOnly
Reject {Assert-GraphUsb $part $disk $volume};$disk.IsReadOnly=$false
$temp=Join-Path ([IO.Path]::GetTempPath()) ('graph-prep-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $temp 'EFI/BOOT') -Force | Out-Null
$image=Join-Path $temp 'source.efi';$boot=Join-Path $temp 'EFI/BOOT/BOOTX64.EFI'
[IO.File]::WriteAllText($image,'mock diagnostic');[IO.File]::WriteAllText($boot,'original boot')
$old=Get-GraphHash $boot;$hash=Get-GraphHash $image
Reject {Copy-GraphBoot $temp $image ('0'*64)}
if((Get-GraphHash $boot) -cne $old){throw 'Rejected copy changed boot file'}
$receipt=Copy-GraphBoot $temp $image $hash
if((Get-GraphHash $boot) -cne $hash -or $receipt.PreviousBootSha256 -cne $old){throw 'Staging/readback mismatch'}
$backup=Join-Path $temp ('EFI/BOOT/BEFORE-GRAPH-'+$old+'.EFI')
if((Get-GraphHash $backup) -cne $old){throw 'Original boot backup mismatch'}
[IO.File]::WriteAllText((Join-Path $temp 'RTX3090-UNLOCK/DIAG00.TXT'),'preserved capture')
Reject {Copy-GraphBoot $temp $image $hash}
if([IO.File]::ReadAllText((Join-Path $temp 'RTX3090-UNLOCK/DIAG00.TXT')) -cne 'preserved capture'){throw 'Capture was changed'}
Write-Host 'PASS: exact-machine refusal, secondary GPU refusal, USB/system/filesystem refusal, hash guard, backup/readback, capture preservation.'
# Keep the tiny mock directory for review; no recursive filesystem cleanup.
