# Offline image/identity/staging models only; sample GUID images must never be booted.
[CmdletBinding()]
param([string]$FreshBuild)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-resource-capture.ps1')
. (Join-Path $PSScriptRoot 'resource-template.ps1')
function Reject([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw 'Expected refusal absent.'}}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('resource-template-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$g=[guid]'12345678-1234-4abc-9def-0123456789ab'
Reject {New-GuResourceTemplate $repo ([guid]::Empty) 'issue172' (Join-Path $temp 'empty')}
Reject {New-GuResourceTemplate $repo ([guid]'a2b4c6d8-1357-49ab-bcde-102030405060') 'issue172' (Join-Path $temp 'sentinel')}
Reject {New-GuResourceTemplate $repo $g 'issue31' (Join-Path $temp 'wrong-case')}
$out=New-GuResourceTemplate $repo $g 'issue172' (Join-Path $temp 'valid')
$raw=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'resource-template/probe-bus8.template'))
$image=Join-Path $out 'BOOTX64.EFI';$bytes=[IO.File]::ReadAllBytes($image)
for($i=0;$i -lt $raw.Length;$i++){
 if(($i -lt 26624 -or $i -ge 26640) -and $raw[$i] -ne $bytes[$i]){throw 'Bytes outside GUID changed.'}
}
for($i=0;$i -lt 16;$i++){if($bytes[26624+$i] -ne $g.ToByteArray()[$i]){throw 'GUID byte order mismatch.'}}
Reject {New-GuResourceTemplate $repo $g 'issue172' $out}
$mock=Join-Path $temp 'mock-source';$mb=Join-Path $mock 'research/profile/resource-template'
New-Item -ItemType Directory -Path $mb -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'resource-template/template.json'),(Join-Path $PSScriptRoot 'resource-template/probe-bus8.template') -Destination $mb
Reject {New-GuResourceTemplate $mock $g 'issue172' (Join-Path $temp 'missing-source')}
$bad=[byte[]]$raw.Clone();$bad[4096]=$bad[4096] -bxor 1
[IO.File]::WriteAllBytes((Join-Path $mb 'probe-bus8.template'),$bad)
Reject {New-GuResourceTemplate $mock $g 'issue172' (Join-Path $temp 'corrupt')}
$p=Read-ProbeConfiguration 'issue172'
$b=[pscustomobject]@{Manufacturer='Gigabyte Technology Co., Ltd.';Product='X570 AORUS ELITE'}
$bi=[pscustomobject]@{SMBIOSBIOSVersion='F41c'};$cpu=[pscustomobject]@{Name='AMD Ryzen 7 5800X 8-Core Processor'}
$v=[pscustomobject]@{PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_147D10DE\PRIVATE'}
Assert-PinnedProbe $p $b $bi $cpu @($v)
$bi.SMBIOSBIOSVersion='wrong';Reject {Assert-PinnedProbe $p $b $bi $cpu @($v)};$bi.SMBIOSBIOSVersion='F41c'
$v.PNPDeviceID='PCI\VEN_10DE&DEV_2204&SUBSYS_000010DE\PRIVATE';Reject {Assert-PinnedProbe $p $b $bi $cpu @($v)}
$usb=Join-Path $temp 'mock-usb';New-Item -ItemType Directory -Path (Join-Path $usb 'RTX3090-UNLOCK'),(Join-Path $usb 'EFI/BOOT') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $usb 'RTX3090-UNLOCK/DIAG00.TXT'),'original graph')
$boot=Join-Path $usb 'EFI/BOOT/BOOTX64.EFI';[IO.File]::WriteAllText($boot,'original graph loader');$old=ProbeHash $boot
Stage-Probe $usb $image (ProbeHash $image) 'issue172' (ProbeHash (Join-Path $PSScriptRoot 'probe-configurations/issue172.json'))
$archive=@(Get-ChildItem -LiteralPath $usb -Directory|Where-Object {$_.Name -like 'RTX3090-UNLOCK.before-probe-*'})
if($archive.Count -ne 1 -or [IO.File]::ReadAllText((Join-Path $archive[0].FullName 'DIAG00.TXT')) -cne 'original graph' -or
 (ProbeHash (Join-Path $usb ('EFI/BOOT/BEFORE-PROBE-'+$old+'.EFI'))) -cne $old){throw 'Graph/boot backup preservation failed.'}
Reject {Stage-Probe $usb $image (ProbeHash $image) 'issue172'}
if($FreshBuild){if((ProbeHash $FreshBuild) -cne (ProbeHash $image)){throw 'Independent compile equivalence failed.'};Write-Host 'PASS: exact byte equivalence with independent sample-GUID resource compile.'}
Write-Host 'PASS: GUID-only bytes/order, source/manifest pins, case/GUID/overwrite refusals, exact machine, graph archive/loader backup/readback/no-repeat. No real hardware.'
