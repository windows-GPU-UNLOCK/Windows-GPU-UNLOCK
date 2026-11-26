# GPL-2.0-only. Vibecoded with love by Claude.
# Put the GPU-UNLOCK boot menu (build-menu.ps1 output) on the stick.
#   dump-phase menu: EFI\BOOT\BOOTX64.EFI = menu, EFI\GPU-UNLOCK\PROBE.EFI = generic probe.
#                    Dumps taken with a different probe build are archived, as new-machine.ps1 does.
#   unlock menu:     run after the project staging (new-machine.ps1 -StageUnlock) has put the
#                    wrapper, child and assets on the stick; adds EFI\GPU-UNLOCK\UNLOCK.EFI too.
# Any other loader found in EFI\BOOT\BOOTX64.EFI is kept in RTX3090-UNLOCK\backup\.
param([Parameter(Mandatory)][ValidatePattern('^[D-Zd-z]$')][string]$Drive)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$m=Get-Content -LiteralPath (Join-Path $here 'build\menu-manifest.json') -Raw | ConvertFrom-Json
function Sha([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
$part=Get-Partition -DriveLetter $Drive;$disk=Get-Disk -Number $part.DiskNumber;$vol=Get-Volume -DriveLetter $Drive
if($disk.BusType -ne 'USB' -or $vol.FileSystem -ne 'FAT32' -or $part.IsSystem -or $disk.IsBoot){throw "$($Drive): is not a FAT32 USB data stick"}
$usb="$($Drive.ToUpperInvariant()):"
$logDir=Join-Path $usb 'RTX3090-UNLOCK'
$menuSrc=Join-Path $here 'build\MENU.EFI'
if((Sha $menuSrc) -ne $m.Menu){throw 'MENU.EFI does not match menu-manifest.json; rebuild the menu'}
$items=@($m.Probe);if($m.Unlock){$items+=$m.Unlock}
foreach($item in $items){if((Sha $item.Source) -ne $item.Sha256){throw "Source changed since the menu was built: $($item.Source); rebuild the menu"}}
$boot=Join-Path $usb 'EFI\BOOT\BOOTX64.EFI'
$current=if(Test-Path -LiteralPath $boot){Sha $boot}else{''}
$probeOnStick=Join-Path $usb 'EFI\GPU-UNLOCK\PROBE.EFI'
$unlockOnStick=Join-Path $usb 'EFI\GPU-UNLOCK\UNLOCK.EFI'
[void][IO.Directory]::CreateDirectory($logDir)

if($m.Mode -eq 'unlock'){
 # The project staging just wrote the wrapper to BOOTX64.EFI, or an earlier menu already fronts it.
 $wrapperThere=($current -eq $m.Unlock.Sha256) -or ((Test-Path -LiteralPath $unlockOnStick) -and (Sha $unlockOnStick) -eq $m.Unlock.Sha256)
 if(!$wrapperThere){throw "The stick does not hold this unlock build; run make-stick.ps1 -StageUnlock (project staging) first"}
 if(!(Test-Path -LiteralPath (Join-Path $usb 'EFI\WindowsGPUUnlock\UNLOCK-HEADLESS.EFI'))){throw 'The unlock child is missing on the stick; run the project staging first'}
 if(!(Test-Path -LiteralPath (Join-Path $logDir 'ASSETS'))){throw 'Firmware assets are missing on the stick; run the project staging first'}
} else {
 # Dumps must all come from one probe build: archive them if the probe changes.
 $sameProbe=($current -eq $m.Probe.Sha256) -or ((Test-Path -LiteralPath $probeOnStick) -and (Sha $probeOnStick) -eq $m.Probe.Sha256)
 $dumps=@(Get-ChildItem -LiteralPath $logDir -File | Where-Object {$_.Name -match '^(DIAG\d\d\.TXT|IMG\d\d\.BIN|PROM\.BIN)$'})
 if($dumps.Count -and !$sameProbe){
  $keep=Join-Path $logDir ('old-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
  [void][IO.Directory]::CreateDirectory($keep);$dumps | Move-Item -Destination $keep
  "  dumps from another probe build moved to $keep"
 }
 'READ-ONLY PROBE dumps (research/profile/build-probe.ps1, started from the GPU-UNLOCK menu item 2): DIAGnn.TXT, PROM.BIN, IMGnn.BIN.' |
  Set-Content -LiteralPath (Join-Path $logDir 'README.TXT') -Encoding ascii
}
# Keep any loader we did not put there ourselves.
$ours=@($m.Menu,$m.Probe.Sha256);if($m.Unlock){$ours+=$m.Unlock.Sha256}
if($current -and $current -notin $ours){
 $bak=Join-Path $logDir ('backup\BOOTX64-'+$current.Substring(0,12)+'.EFI')
 if(!(Test-Path -LiteralPath $bak)){[void][IO.Directory]::CreateDirectory((Split-Path $bak));Copy-Item -LiteralPath $boot -Destination $bak;"  previous BOOTX64.EFI kept as $bak"}
}
[void][IO.Directory]::CreateDirectory((Join-Path $usb 'EFI\GPU-UNLOCK'))
[void][IO.Directory]::CreateDirectory((Join-Path $usb 'EFI\BOOT'))
function Put([string]$src,[string]$rel,[string]$hash){
 $dst=Join-Path $usb $rel
 Copy-Item -LiteralPath $src -Destination $dst -Force
 if((Sha $dst) -ne $hash){throw "Copy verification failed: $rel"}
 "  $rel  $hash"
}
if($m.Unlock){Put $m.Unlock.Source $m.Unlock.Target $m.Unlock.Sha256}
Put $m.Probe.Source $m.Probe.Target $m.Probe.Sha256
Put $menuSrc 'EFI\BOOT\BOOTX64.EFI' $m.Menu
@(
 'GPU-UNLOCK stick (tools/usb-stick, Vibecoded with love by Claude)',
 ('Menu: '+$m.Mode+'   profile: '+$m.Profile+'   default: item '+$m.DefaultItem+' after '+$m.TimeoutSeconds+' s'),
 'EFI\BOOT\BOOTX64.EFI       boot menu: 1 unlock, 2 read-only GPU dump, 3 Windows without unlock',
 ('EFI\GPU-UNLOCK\UNLOCK.EFI  headless USB wrapper '+$(if($m.Unlock){$m.Unlock.Sha256}else{'(not built yet: dump phase)'})),
 ('EFI\GPU-UNLOCK\PROBE.EFI   generic read-only probe '+$m.Probe.Sha256),
 'EFI\WindowsGPUUnlock\      unlock child (path fixed by the wrapper)',
 'RTX3090-UNLOCK\ASSETS\     NVIDIA firmware assets - personal use only, never share',
 'RTX3090-UNLOCK\            boot logs (HLS*.TXT, AUTO*\REPORT.TXT) and probe dumps (DIAG*, PROM.BIN, IMG*)'
) | Set-Content -LiteralPath (Join-Path $usb 'GPU-UNLOCK.TXT') -Encoding ascii
"$($m.Mode) menu staged on $usb."
