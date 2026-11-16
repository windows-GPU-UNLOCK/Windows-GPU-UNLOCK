# GPL-2.0-only. Copy a build-usb.ps1 package and the five local assets to a FAT32 USB stick.
# Files only: no partitioning, formatting, boot entries or firmware settings change.
param([Parameter(Mandatory)][ValidatePattern('^[D-Zd-z]$')][string]$Drive,[Parameter(Mandatory)][string]$Assets)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$part=Get-Partition -DriveLetter $Drive;$disk=Get-Disk -Number $part.DiskNumber;$vol=Get-Volume -DriveLetter $Drive
if($disk.BusType -ne 'USB' -or $vol.FileSystem -ne 'FAT32' -or $part.IsSystem -or $disk.IsBoot){throw "$($Drive): is not a FAT32 USB data stick"}
$usb="$($Drive.ToUpperInvariant()):"
# With protection active on C:, the changed boot chain (USB loader, Secure Boot off) makes
# Windows Boot Manager ask for the BitLocker recovery key while the display is still dark.
# Without input it powers off after about a minute, which looks like a failed handoff (#125).
# This tool never changes encryption settings; refuse before the first write instead.
# Fail closed: returns 'Off' or 'On' only for a recognized state, otherwise $null.
# Never cast a missing value to [int], because $null becomes 0 and would read as Off.
function Get-BitLockerProtection {
 try{
  $s=[string](Get-BitLockerVolume -MountPoint C: -ErrorAction Stop).ProtectionStatus
  if($s -eq 'Off'){return 'Off'};if($s -eq 'On'){return 'On'}
  return $null # Unknown (locked volume) or empty
 }catch{} # not elevated, cmdlet missing or failed: try the shell property
 # Shell property 1 on, 3 encrypting, 6 on/locked; 2 off, 4 decrypting, 5 suspended.
 # Null, 0 or anything else is unrecognized.
 try{$v=(New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection')}catch{return $null}
 $n=0;if(-not [int]::TryParse([string]$v,[ref]$n)){return $null}
 if(@(2,4,5) -contains $n){return 'Off'};if(@(1,3,6) -contains $n){return 'On'}
 return $null
}
$bitLocker=Get-BitLockerProtection
if($bitLocker -eq 'On'){throw 'BitLocker protection on C: is active. Keep the recovery key at hand, then suspend it in an elevated PowerShell: Suspend-BitLocker -MountPoint C: -RebootCount 0 (see docs/HEADLESS-USB.en.md)'}
if($bitLocker -ne 'Off'){throw 'BitLocker protection state of C: could not be verified, so nothing was written. Rerun from an elevated PowerShell; if it still stops, check manage-bde -status C: (see docs/HEADLESS-USB.en.md)'}
function Sha([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Put([string]$src,[string]$rel,[string]$hash) {
 if((Sha $src) -ne $hash){throw "Source does not match its manifest: $src"}
 $dst=Join-Path $usb $rel;[void][IO.Directory]::CreateDirectory((Split-Path $dst))
 Copy-Item -LiteralPath $src -Destination $dst -Force
 if((Sha $dst) -ne $hash){throw "Copy verification failed: $rel"}
 "{0,-48} {1}" -f $rel,$hash
}
$m=Get-Content (Join-Path $repo 'internal-boot/boot/build/headless/usb-manifest.json') -Raw | ConvertFrom-Json
# Validate identity before the first destination write, including missing/unknown
# profile names which must never bypass the local evidence gate.
. (Join-Path $repo 'internal-boot/unlock/local-profile.ps1')
Assert-GuUsbManifest $repo $m
$child=Join-Path $repo 'internal-boot/unlock/build/experimental/entryLatchedSs1Full/internal/automatic/headless-research/usb/RTX3090-EXPERIMENTAL-entryLatchedSs1Full-INTERNAL-AUTO-HEADLESS-RESEARCH-USB.EFI'
$boot=Join-Path $usb 'EFI\BOOT\BOOTX64.EFI'
if(Test-Path -LiteralPath $boot) {
 $bak=Join-Path $usb ('RTX3090-UNLOCK\backup\BOOTX64-'+(Sha $boot).Substring(0,12)+'.EFI')
 if(!(Test-Path -LiteralPath $bak)){[void][IO.Directory]::CreateDirectory((Split-Path $bak));Copy-Item -LiteralPath $boot -Destination $bak}
 "previous BOOTX64.EFI kept as $bak"
}
Put (Join-Path $repo 'internal-boot/boot/build/headless/HEADLESS.EFI') 'EFI\BOOT\BOOTX64.EFI' $m.EfiSha256
Put $child 'EFI\WindowsGPUUnlock\UNLOCK-HEADLESS.EFI' $m.ChildSha256
foreach($a in (Get-Content (Join-Path $repo 'internal-boot/unlock/assets.json') -Raw | ConvertFrom-Json)) {
 $src=Join-Path $Assets $a.Name
 if((Get-Item -LiteralPath $src).Length -ne $a.Bytes){throw ('Asset size mismatch: '+$a.Name)}
 Put $src ('RTX3090-UNLOCK\ASSETS\'+$a.Name) $a.Sha256.ToLowerInvariant()
}
"Staged $($m.HardwareProfile) on $usb. Boot it once with the firmware boot menu before making it a default boot device."
