# Inventory mocks and temporary files only; no GPU, firmware or real disk queries.
param([string]$Python='python')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-zotac-ga106.ps1') -Python $Python
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};if(!$failed){throw 'Expected refusal was absent.'}}
$board=[pscustomobject]@{Manufacturer='Gigabyte Technology Co., Ltd.';Product='B650M DS3H'}
$bios=[pscustomobject]@{SMBIOSBIOSVersion='F21'};$cpu=[pscustomobject]@{Name='AMD Ryzen 5 7600 6-Core Processor'}
$gpu=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2504&SUBSYS_263019DA&REV_A1\PRIVATE'}
$amd=[pscustomobject]@{PNPDeviceID='PCI\VEN_1002&DEV_164E&SUBSYS_D0001458\PRIVATE'}
Assert-Zotac114 $board $bios $cpu @($gpu,$amd)
Reject {Assert-Zotac114 $board $bios $cpu @($gpu)}
$bios.SMBIOSBIOSVersion='other';Reject {Assert-Zotac114 $board $bios $cpu @($gpu,$amd)};$bios.SMBIOSBIOSVersion='F21'
$wrong=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2504&SUBSYS_000019DA\PRIVATE'}
Reject {Assert-Zotac114 $board $bios $cpu @($wrong,$amd)}
Reject {Assert-Zotac114 $board $bios $cpu @($gpu,$gpu,$amd)}
$part=[pscustomobject]@{IsSystem=$false;IsBoot=$false}
$disk=[pscustomobject]@{BusType='USB';UniqueId='mock';IsBoot=$false;IsSystem=$false;IsOffline=$false;IsReadOnly=$false}
$volume=[pscustomobject]@{FileSystem='FAT32';SizeRemaining=512MB}
Assert-ProbeUsb $part $disk $volume
$disk.BusType='SATA';Reject {Assert-ProbeUsb $part $disk $volume};$disk.BusType='USB'
$volume.SizeRemaining=1MB;Reject {Assert-ProbeUsb $part $disk $volume};Assert-ProbeUsb $part $disk $volume -ReadOnly
$root=Join-Path ([IO.Path]::GetTempPath()) ('zotac-probe-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'EFI/BOOT'),(Join-Path $root 'RTX3090-UNLOCK') -Force | Out-Null
$oldLog=Join-Path $root 'RTX3090-UNLOCK/DIAG00.TXT';[IO.File]::WriteAllText($oldLog,'original refusal')
$boot=Join-Path $root 'EFI/BOOT/BOOTX64.EFI';[IO.File]::WriteAllText($boot,'old boot loader');$oldHash=ProbeHash $boot
$image=Join-Path $root 'source.efi';[IO.File]::WriteAllText($image,'mock probe');$hash=ProbeHash $image
Reject {Stage-Probe $root $image ('0'*64)}
if(!(Test-Path -LiteralPath $oldLog) -or (ProbeHash $boot) -cne $oldHash){throw 'Rejected stage mutated existing inputs.'}
Stage-Probe $root $image $hash
$archives=@(Get-ChildItem -LiteralPath $root -Directory | Where-Object {$_.Name -like 'RTX3090-UNLOCK.before-probe-*'})
if($archives.Count -ne 1 -or [IO.File]::ReadAllText((Join-Path $archives[0].FullName 'DIAG00.TXT')) -cne 'original refusal'){throw 'Archived log not preserved.'}
$newFiles=@(Get-ChildItem -LiteralPath (Join-Path $root 'RTX3090-UNLOCK') -Force)
if($newFiles.Count -ne 1 -or $newFiles[0].Name -cne 'probe114-stage.json'){throw 'Unexpected data in the new capture folder.'}
if((ProbeHash $boot) -cne $hash -or (ProbeHash (Join-Path $root ('EFI/BOOT/BEFORE-PROBE-'+$oldHash+'.EFI'))) -cne $oldHash){throw 'Boot/backup hash mismatch.'}
Reject {Stage-Probe $root $image $hash}
if(@(Get-ChildItem -LiteralPath $root -Directory | Where-Object {$_.Name -like 'RTX3090-UNLOCK.before-probe-*'}).Count -ne 1){throw 'Repeat stage archived the current run.'}
[IO.File]::WriteAllText((Join-Path $root 'EFI/BOOT/PROBE-NEW.EFI'),'partial')
Reject {Stage-Probe $root $image $hash}
Write-Host 'PASS: exact target/board/companion refusals, media/space refusals, old boot backup, archive preservation, new-copy readback and partial-stage refusal.'
$captureFolder=Join-Path $root 'RTX3090-UNLOCK';$publicFolder=Join-Path $root 'public'
New-Item -ItemType Directory -Path $publicFolder | Out-Null
$sample="PRIVATE-LOCAL-PATH`nincomplete reason=probe-unreviewed-envelope status=0x8000000000000003`nmmio off=0x00000000 status=0x8000000000000007 value=0xdeadbeef`ncapture-complete=0`ndiagnostic-result status=0x8000000000000006`n"
[IO.File]::WriteAllText((Join-Path $captureFolder 'DIAG00.TXT'),$sample)
foreach($case in @('issue31','issue173')){
Export-ProbeReport ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) $captureFolder $publicFolder $Python $case
$json=[IO.File]::ReadAllText((Join-Path $publicFolder 'report.json'));$public=$json | ConvertFrom-Json
if($public.Test -cne ($case+'-pinned-probe-review') -or $json.Contains('PRIVATE') -or $public.WriteEligible -ne $false -or $public.HardwareVerified -ne $false -or
   $public.CaptureMarkers.Count -ne 1 -or !$public.CaptureMarkers[0].EnvelopeRefusalRecorded -or $public.CaptureMarkers[0].FailedMmioReads -ne 1){throw 'Offline public report failed privacy/refusal checks.'}
}
Write-Host 'PASS: real offline checker export preserves failure markers and excludes private log text.'
# Tiny mock directory retained for inspection; no recursive cleanup.
