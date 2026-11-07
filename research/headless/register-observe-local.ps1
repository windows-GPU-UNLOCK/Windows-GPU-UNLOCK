# GPL-2.0-only. LOCAL port registration for the b760m-3080lhr observation EFI.
# Stages the locally built DIAGNOSTIC.EFI onto the unlock ESP and appends a
# manual F8 boot entry. Preserves existing boot order; exports a BCD backup.
# Modeled on register-observe.ps1; accepts our local build hash by design.
param([switch]$Register)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$diag=Join-Path $repo 'internal-boot/boot/build/diagnostic/DIAGNOSTIC.EFI'
$m=Get-Content -LiteralPath (Join-Path $repo 'internal-boot/boot/build/diagnostic/manifest.json') -Raw | ConvertFrom-Json
if($m.Mode -ne 'graph-capture-then-normal-windows' -or $m.CanUnlock -ne $false -or $m.CanDetach -ne $false -or $m.WritesFirmwareVariables -ne $false -or $m.HardwareProfile -ne 'b760m-3080lhr'){throw 'Unexpected diagnostic capabilities'}
if($m.EfiSha256 -ne (Get-FileHash -LiteralPath $diag).Hash){throw 'Diagnostic build hash mismatch'}
if(Confirm-SecureBootUEFI){throw 'Unsigned observation EFI requires Secure Boot disabled'}
$encryption=Get-BitLockerVolume -MountPoint C:
if([int]$encryption.VolumeStatus -ne 0 -or [int]$encryption.ProtectionStatus -ne 0){throw 'BitLocker must stay off for this flow'}
if(!(Test-Path -LiteralPath 'V:\')){throw 'Unlock ESP V: is not mounted; re-run the mount step'}
$config=Get-Content -LiteralPath (Join-Path $repo 'internal-boot/local-config.json') -Raw | ConvertFrom-Json
if($config.UnlockDriveLetter -ne 'V'){throw 'local-config unlock drive changed'}
$root='V:\'
$target=Join-Path $root 'EFI\WindowsGPUUnlock\OBSERVE.EFI'
$path='\EFI\WindowsGPUUnlock\OBSERVE.EFI'
$name='GPU Observe NO UNLOCK (b760m-3080lhr)'
if(Test-Path -LiteralPath $target){if((Get-FileHash -LiteralPath $target).Hash -ne $m.EfiSha256){throw 'Different observation EFI exists; never overwrite'}}
else{[IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null;[IO.File]::Copy($diag,$target,$false)}
# probe.c dumps driver images to the volume holding an existing \RTX3090-UNLOCK
[void][IO.Directory]::CreateDirectory((Join-Path $root 'RTX3090-UNLOCK'))
function Bcd([string[]]$Arguments){$lines=@(& bcdedit @Arguments);if($LASTEXITCODE -ne 0){throw ('BCDEdit failed: '+($Arguments -join ' '))};return ($lines -join "`r`n")}
function Ids([string]$Text){return @([regex]::Matches($Text,'(?mi)^(?:identifier|标识符)\s+(\{[0-9a-f-]{36}\})') | ForEach-Object {$_.Groups[1].Value})}
function Order([string]$Text){
 $m2=[regex]::Match($Text,'(?ms)^displayorder\s+(.*?)(?=\r?\n\S|\z)');if(!$m2.Success){throw 'No firmware order'}
 $v=@([regex]::Matches($m2.Groups[1].Value,'\{(?:bootmgr|[0-9a-f-]{36})\}') | ForEach-Object {$_.Value})
 if($v -notcontains '{bootmgr}' -or @($v | Select-Object -Unique).Count -ne $v.Count){throw 'Invalid firmware order'};return $v
}
if(!$Register){Write-Output 'Observation EFI staged only; no boot entry/order changes.';return}
$fw=Bcd @('/enum','{fwbootmgr}');$order=Order $fw;$firmwareBefore=Bcd @('/enum','firmware')
if($fw -match '(?mi)^bootsequence\s+'){throw 'Pending BootNext: registration refused'}
# Clean an orphaned entry from a previous failed attempt, if any.
foreach($id in (Ids (Bcd @('/enum','all')))){
 $e=Bcd @('/enum',$id)
 if($e -match ('(?m)^description\s+'+[regex]::Escape($name)+'\s*$')){
  [void](Bcd @('/delete',$id));$fw=Bcd @('/enum','{fwbootmgr}');$order=Order $fw
 }
}
$beforeIds=Ids (Bcd @('/enum','all'))
$backup=Join-Path $env:ProgramData ('WindowsGPUUnlock\ResearchBackups\'+(Get-Date -Format 'yyyyMMdd-HHmmssfff'))
[void][IO.Directory]::CreateDirectory($backup)
[void](Bcd @('/export',(Join-Path $backup 'BCD-export')))
[IO.File]::WriteAllText((Join-Path $backup 'firmware-before.txt'),$firmwareBefore)
$new=$null
try{
 [void](Bcd @('/copy','{bootmgr}','/d',$name))
 $after=Ids (Bcd @('/enum','all'))
 $new=@($after | Where-Object {$beforeIds -notcontains $_})[0]
 if(!$new){throw 'No new boot entry appeared'}
 [void](Bcd @('/set',$new,'device','partition=V:'))
 [void](Bcd @('/set',$new,'path',$path))
 [void](Bcd (@('/set','{fwbootmgr}','displayorder') + @($order) + @($new)))
} catch {
 if($new -and ((Bcd @('/enum','all')) -match [regex]::Escape($new))){[void](Bcd @('/delete',$new))}
 [void](Bcd (@('/set','{fwbootmgr}','displayorder') + @($order)))
 throw
}
$entry=Bcd @('/enum',$new);$after=Bcd @('/enum','{fwbootmgr}')
if(((Order $after) -join ',') -cne ((@($order)+@($new)) -join ',') -or $entry -notmatch ('(?mi)^path\s+'+[regex]::Escape($path)+'\s*$') -or $entry -notmatch ('(?m)^description\s+'+[regex]::Escape($name)+'\s*$') -or $entry -notmatch '(?mi)^device\s+partition=V:\s*$'){[void](Bcd @('/delete',$new));[void](Bcd (@('/set','{fwbootmgr}','displayorder') + @($order)));throw 'Observation entry verification failed'}
Write-Output "Registered '$name' at the end of the F8 menu. Default order prefix preserved. Backup: $backup"
