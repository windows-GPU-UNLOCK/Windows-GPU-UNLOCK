# GPL-2.0-only. Vibecoded with love by Claude.
# Builds a GPU-UNLOCK USB stick for THIS machine in two runs (see README.md):
#   run 1: prerequisites (LLVM 20.1.8, firmware assets, no WSL) + read-only probe + dump-phase menu
#          -> boot the stick twice after full shutdowns and pick menu item 2 (GPU dump)
#   run 2: LOCAL profile + 22 host tests + USB package (research/profile/new-machine.ps1, unchanged)
#          and, with -StageUnlock, the unlock on the stick behind the normal menu.
# Use the same command line both times. It never changes BIOS or Windows settings, never
# partitions or formats, and never touches the GPU. Only booting the stick does that, and the
# unlock is only written with -StageUnlock.
# Do not pipe its output (*>&1, Tee-Object) in Windows PowerShell 5.1: Python test output on
# stderr then becomes a terminating error inside the project's scripts.
param(
 [Parameter(Mandatory)][ValidatePattern('^[D-Zd-z]$')][string]$Drive,
 [switch]$StageUnlock,
 [string]$WorkDir=(Join-Path $env:LOCALAPPDATA 'GPU-UNLOCK'),
 [string]$Clang,[string]$LldLink,[string]$Python,[string]$VcVars,
 [ValidateRange(1,99)][int]$MenuTimeout=20,
 [ValidateRange(1,3)][int]$MenuDefault=1,
 [switch]$ArchiveCaptures,
 [switch]$MenuOnly,
 [switch]$Check
)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$repo=[IO.Path]::GetFullPath((Join-Path $here '..\..'))
$newMachine=Join-Path $repo 'research\profile\new-machine.ps1'
if(!(Test-Path -LiteralPath $newMachine)){throw "Run this from a Windows-GPU-UNLOCK checkout (missing $newMachine)"}
$prereqs=Join-Path $here 'prereqs.py'
. (Join-Path $repo 'research\profile\probe-manifest.ps1')
function Sha([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Step([string]$t){Write-Host "`n== $t" -ForegroundColor Cyan}
function Note([string]$t){Write-Host "   $t"}
function Warn([string]$t){Write-Host "   ! $t" -ForegroundColor Yellow}

# ---------------------------------------------------------------- stick
Step "USB stick $($Drive.ToUpperInvariant()):"
$part=Get-Partition -DriveLetter $Drive;$disk=Get-Disk -Number $part.DiskNumber;$vol=Get-Volume -DriveLetter $Drive
if($disk.BusType -ne 'USB' -or $vol.FileSystem -ne 'FAT32' -or $part.IsSystem -or $disk.IsBoot){throw "$($Drive): is not a FAT32 USB data stick (format it FAT32 yourself; this script never formats)"}
$usb="$($Drive.ToUpperInvariant()):";$logDir=Join-Path $usb 'RTX3090-UNLOCK'
Note "$($disk.FriendlyName), FAT32, $([math]::Round($vol.Size/1GB,1)) GB"

# ---------------------------------------------------------------- python
Step 'Python 3.14'
if(!$Python){
 try{$Python=(& py -3.14 -c 'import sys;print(sys.executable)' 2>$null)}catch{$Python=$null}
 if(!$Python -or $LASTEXITCODE -ne 0){throw 'Python 3.14 not found. Install it from python.org (the "py" launcher must see it) or pass -Python C:\...\python.exe'}
}
$pyVersion=& $Python -I -c 'import sys;print(sys.version_info[0]*100+sys.version_info[1])'
if([int]$pyVersion -lt 314){throw "$Python is older than 3.14"}
Note $Python

# ---------------------------------------------------------------- Windows settings
Step 'Windows and firmware settings'
$espList=@(Get-Partition | Where-Object IsSystem)
if($espList.Count -ne 1){throw "Expected exactly one EFI system partition, found $($espList.Count)"}
$esp=[guid]$espList[0].Guid
Note "Windows ESP $esp"
$secureBoot=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
$fastStartup=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
$bitlocker=$null;try{$bitlocker=(New-Object -ComObject Shell.Application).NameSpace("$env:SystemDrive\").Self.ExtendedProperty('System.Volume.BitLockerProtection')}catch{}
if($secureBoot -eq 1){Warn 'Secure Boot is ON. The stick is unsigned and will not boot until you disable Secure Boot in the BIOS.'}else{Note 'Secure Boot off'}
if($bitlocker -in @(1,3,5,6)){Warn "BitLocker protects $env:SystemDrive. Disabling Secure Boot will ask for the recovery key: have it ready (aka.ms/myrecoverykey) or turn BitLocker off first."}
if($fastStartup -eq 1){
 Warn 'Fast Startup is ON. "Shut down" must be a real power-off for the dumps and the unlock.'
 Warn 'Turn it off (administrator PowerShell):  reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f'
 if(!$Check){throw 'Fast Startup must be off'}
}else{Note 'Fast Startup off'}

# ---------------------------------------------------------------- toolchain
Step 'LLVM 20.1.8 and MSVC'
function Test-Clang([string]$c){if(!$c -or !(Test-Path -LiteralPath $c)){return $false};return ((& $c --version) -join ' ') -match 'clang version 20\.1\.8'}
if(!$Clang){
 foreach($c in @((Join-Path $WorkDir 'LLVM20\bin\clang.exe'),'C:\TOOLS\LLVM20\bin\clang.exe')){if(Test-Clang $c){$Clang=$c;break}}
}
if(!$Clang){
 if($Check){Warn "LLVM 20.1.8 missing; a normal run downloads it into $WorkDir\LLVM20 (896 MiB)"}
 else{
  & $Python -I $prereqs llvm --dest (Join-Path $WorkDir 'LLVM20') --cache (Join-Path $WorkDir 'downloads')
  if($LASTEXITCODE -ne 0){throw 'LLVM setup failed'}
  $Clang=Join-Path $WorkDir 'LLVM20\bin\clang.exe'
 }
}
if($Clang){
 if(!(Test-Clang $Clang)){throw "$Clang is not clang 20.1.8"}
 if(!$LldLink){$LldLink=Join-Path (Split-Path $Clang) 'lld-link.exe'}
 if(!(Test-Path -LiteralPath $LldLink)){throw "lld-link not found next to $Clang"}
 Note $Clang
}
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vc=if(Test-Path -LiteralPath $vswhere){& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath}else{$null}
if(!$vc -and !$VcVars){throw 'MSVC C++ build tools not found. Install "Visual Studio Build Tools" with "Desktop development with C++" (MSVC + Windows SDK).'}
Note "MSVC: $(if($VcVars){$VcVars}else{$vc})"

# ---------------------------------------------------------------- firmware assets
Step 'Firmware assets'
$assets=Join-Path $WorkDir 'assets'
$assetOk=$true
foreach($a in (Get-Content -LiteralPath (Join-Path $repo 'internal-boot\unlock\assets.json') -Raw | ConvertFrom-Json)){
 $p=Join-Path $assets $a.Name
 if(!(Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -ne $a.Bytes -or (Sha $p) -ne $a.Sha256.ToLowerInvariant()){$assetOk=$false}
}
if(!$assetOk -and $MenuOnly){Note 'not needed for -MenuOnly'}
elseif(!$assetOk){
 if($Check){Warn "assets missing; a normal run generates them in $assets (downloads about 330 MiB)"}
 else{
  & $Python -I $prereqs firmware --repo $repo --out $assets --cache (Join-Path $WorkDir 'downloads')
  if($LASTEXITCODE -ne 0){throw 'Firmware asset generation failed'}
 }
}else{Note "$assets (all five match assets.json)"}

# ---------------------------------------------------------------- stick state
$need=(Get-Content -LiteralPath (Join-Path $repo 'research\profile\proven.json') -Raw | ConvertFrom-Json).min_captures
function Get-Captures {@(Get-ChildItem -LiteralPath $logDir -Filter 'DIAG??.TXT' -File -ErrorAction SilentlyContinue | Where-Object {
 $t=[IO.File]::ReadAllText($_.FullName);$t.Contains('probe-pci-handles=') -and $t.Contains("capture-complete=1`r`n")})}
$usbManifestPath=Join-Path $repo 'internal-boot\boot\build\headless\usb-manifest.json'
function Get-UnlockOnStick {
 if(!(Test-Path -LiteralPath $usbManifestPath)){return $false}
 $h=(Get-Content -LiteralPath $usbManifestPath -Raw | ConvertFrom-Json).EfiSha256
 foreach($f in @('EFI\GPU-UNLOCK\UNLOCK.EFI','EFI\BOOT\BOOTX64.EFI')){$p=Join-Path $usb $f;if((Test-Path -LiteralPath $p) -and (Sha $p) -eq $h){return $true}}
 return $false
}
function Describe-Stick {
 $bootFile=Join-Path $usb 'EFI\BOOT\BOOTX64.EFI'
 if(!(Test-Path -LiteralPath $bootFile)){return 'nothing (no EFI\BOOT\BOOTX64.EFI)'}
 $h=Sha $bootFile;$known=@{}
 $pm=Join-Path $repo 'internal-boot\boot\build\probe-generic\manifest.json'
 if(Test-Path -LiteralPath $pm){$known[(Get-Content -LiteralPath $pm -Raw | ConvertFrom-Json).EfiSha256]='the read-only probe (no menu)'}
 if(Test-Path -LiteralPath $usbManifestPath){$known[(Get-Content -LiteralPath $usbManifestPath -Raw | ConvertFrom-Json).EfiSha256]='the unlock wrapper (no menu)'}
 $mm=Join-Path $here 'build\menu-manifest.json'
 if(Test-Path -LiteralPath $mm){$mf=Get-Content -LiteralPath $mm -Raw | ConvertFrom-Json;$known[$mf.Menu]="the GPU-UNLOCK menu ($($mf.Mode))"}
 if($known.ContainsKey($h)){return $known[$h]};return "another loader ($($h.Substring(0,12))), will be kept in RTX3090-UNLOCK\backup"
}
function Build-Probe {
 & (Join-Path $repo 'research\profile\build-probe.ps1') -WindowsEspGuid $esp -Clang $Clang -LldLink $LldLink -Python $Python | Out-Host
 $probe=Join-Path $repo 'internal-boot\boot\build\probe-generic\BOOTX64.EFI'
 Assert-GuGenericProbeManifest $repo (Get-Content -LiteralPath (Join-Path $repo 'internal-boot\boot\build\probe-generic\manifest.json') -Raw | ConvertFrom-Json) $probe
}
function Stage-Menu([switch]$Dump){
 $menuArgs=@{Clang=$Clang;LldLink=$LldLink;Python=$Python;TimeoutSeconds=$MenuTimeout}
 if($Dump){$menuArgs.ProbeOnly=$true;$menuArgs.DefaultItem=3}else{$menuArgs.DefaultItem=$MenuDefault}
 & (Join-Path $here 'build-menu.ps1') @menuArgs | Out-Host
 & (Join-Path $here 'stage-menu.ps1') -Drive $Drive | Out-Host
}

if($ArchiveCaptures){
 Step 'Archive dumps'
 $files=@(Get-ChildItem -LiteralPath $logDir -File -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^(DIAG\d\d\.TXT|IMG\d\d\.BIN|PROM\.BIN)$'})
 if($files.Count){
  $stamp=[DateTime]::Now.ToString('yyyyMMdd-HHmmss')
  $local=Join-Path $WorkDir "captures-archive\$stamp";New-Item -ItemType Directory -Force $local | Out-Null
  $files | Copy-Item -Destination $local
  $old=Join-Path $logDir "old-$stamp";New-Item -ItemType Directory $old | Out-Null
  $files | Move-Item -Destination $old
  Note "$($files.Count) files moved to $old (copy in $local)"
 }else{Note 'no dump files on the stick'}
}

$captures=@(Get-Captures)
$unlockOnStick=Get-UnlockOnStick
Step 'State'
Note "stick boots: $(Describe-Stick)"
Note "complete dumps on the stick: $($captures.Count) of $need"
Note "unlock on the stick: $(if($unlockOnStick){'yes'}else{'no'})"
$evidence=Join-Path $repo 'research\profile\local\test-results.json'
Note "local profile tests: $(if(Test-Path -LiteralPath $evidence){'passed (test-results.json present)'}else{'not run yet'})"

if($MenuOnly){
 Step 'Menu only'
 if($unlockOnStick){Stage-Menu}else{Build-Probe;Stage-Menu -Dump}
 return
}
# A finished stick whose dumps were cleared without -ArchiveCaptures: do not fall back to the dump phase.
$finished=$unlockOnStick -and $captures.Count -lt $need -and !$ArchiveCaptures -and (Test-Path -LiteralPath $evidence)
if($Check){
 if($finished){Note 'Next normal run: nothing to do, the stick already has the unlock (use -MenuOnly or -ArchiveCaptures).'}
 elseif($captures.Count -lt $need){Note 'Next normal run: dump phase (probe + menu on the stick).'}
 elseif($StageUnlock){Note 'Next normal run: profile, 22 host tests, package, unlock + menu on the stick.'}
 else{Note 'Next normal run: profile, 22 host tests and package; add -StageUnlock to also write the unlock.'}
 Note 'Check only: nothing was built or written.';return
}

if($finished){
 Step 'Nothing to do'
 Note 'The stick already holds the unlock for this profile and has no dumps to rebuild from.'
 Note 'Change only the menu: -MenuOnly.  Start over after a BIOS/hardware/Windows change: -ArchiveCaptures.'
 return
}

# ---------------------------------------------------------------- run 1: dump phase
if($captures.Count -lt $need){
 Step 'Dump phase: read-only probe and menu'
 Build-Probe
 Stage-Menu -Dump
 Step 'Next: two GPU dumps'
 Note '1. Start > Shut down (not Restart). Wait until the PC is completely off.'
 Note '2. Power on and boot the stick (first in the BIOS boot order, or via the boot-menu key).'
 Note '3. In the GPU-UNLOCK menu press 2. The dump takes a few seconds, then Windows starts.'
 Note "4. Repeat until there are $need dumps, then run this script again with the same command line."
 Note 'The first boot right after saving BIOS settings is a warm reset: shut down once more before dumping.'
 return
}

# ---------------------------------------------------------------- run 2: profile, tests, package, unlock
$report=& $Python -I (Join-Path $repo 'research\profile\check-compatibility.py') $logDir --json | Out-String | ConvertFrom-Json
$bad=@($report.checks | Where-Object {$_.state -ne 'candidate'})
if($bad.Count){
 Step "Dumps are not usable yet: $($report.status)"
 $bad | ForEach-Object {Warn "$($_.code): $($_.message)"}
 if(@($bad | Where-Object {$_.code -eq 'captures_disagree'}).Count){& $Python -I $prereqs diff --repo $repo --captures $logDir}
 if($report.status -eq 'outside_scope'){throw 'This machine is outside the automatic local-profile route (docs/NEW-MACHINE.en.md). Do not force it.'}
 throw 'Run again with -ArchiveCaptures, then take two new dumps (menu item 2), each after a full shutdown.'
}
Step 'Profile, host tests and package (research/profile/new-machine.ps1)'
$nm=@{Drive=$Drive;WindowsEspGuid=$esp;Assets=$assets;Clang=$Clang;LldLink=$LldLink;Python=$Python}
if($VcVars){$nm.VcVars=$VcVars}
if($StageUnlock){$nm.StageUnlock=$true}
& $newMachine @nm
if(!$?){throw 'new-machine.ps1 failed'}
if(!$StageUnlock){
 Step 'Next: write the unlock'
 Note 'Profile, 22 host tests and the USB package are ready. The stick still has the dump-phase menu.'
 Note 'Run the same command with -StageUnlock to put the unlock on the stick.'
 return
}
Step 'Menu'
Stage-Menu
Step 'Done: the stick is ready'
Note "Menu: 1 = unlock, 2 = GPU dump, 3 = Windows only; item $MenuDefault starts after $MenuTimeout s."
Note 'First unlock: be at the PC. Shut down, power on, boot the stick, let item 1 start, press nothing.'
Note 'The screen goes black for a moment, then Windows starts. If it stays black for minutes:'
Note 'remove the stick, hold the power button, power on again. Windows boots normally.'
Note 'Logs: RTX3090-UNLOCK\AUTO*\REPORT.TXT on the stick (look for FINAL status=0 clean=1).'
