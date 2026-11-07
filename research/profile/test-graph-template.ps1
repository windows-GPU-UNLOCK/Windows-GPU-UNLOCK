# Offline packaged GUID personalization and refusal tests; never boot these test GUIDs.
[CmdletBinding()]
param([string]$FreshBuild)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'prepare-graph.ps1')
. (Join-Path $PSScriptRoot 'graph-template.ps1')
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
function Refuse([scriptblock]$Action){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw 'Expected refusal absent.'}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('graph-template-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
Refuse {New-PinnedGraphFromTemplate $repo ([guid]::Empty) (Join-Path $root 'empty')}
Refuse {New-PinnedGraphFromTemplate $repo ([guid]'a2b4c6d8-1357-49ab-bcde-102030405060') (Join-Path $root 'sentinel')}
$guid=[guid]'12345678-1234-4abc-9def-0123456789ab'
$out=New-PinnedGraphFromTemplate $repo $guid (Join-Path $root 'valid')
$original=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'graph-template/graph-only.template'))
$actual=[IO.File]::ReadAllBytes((Join-Path $out 'GRAPH-ONLY.EFI'))
for($i=0;$i -lt $original.Length;$i++){
 if(($i -lt 10752 -or $i -ge 10768) -and $original[$i] -ne $actual[$i]){throw 'Bytes outside GUID changed.'}
}
for($i=0;$i -lt 16;$i++){if($actual[10752+$i] -ne $guid.ToByteArray()[$i]){throw 'GUID byte order mismatch.'}}
$m=Get-Content -LiteralPath (Join-Path $out 'manifest.json') -Raw|ConvertFrom-Json
if($m.BuildPerformed -ne $false -or $m.CanUnlock -ne $false -or $m.ReadsGpuMmio -ne $false -or $m.SourceInputCount -ne 761){throw 'Scope regression.'}
Refuse {New-PinnedGraphFromTemplate $repo $guid $out}
# A private mock repo permits corruption tests without changing trusted source.
$mock=Join-Path $root 'mock';$base=Join-Path $mock 'research/profile/graph-template'
New-Item -ItemType Directory -Path $base -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'graph-template/graph-only.template'),(Join-Path $PSScriptRoot 'graph-template/template.json') -Destination $base
Refuse {New-PinnedGraphFromTemplate $mock $guid (Join-Path $root 'missing-sources')}
$bad=[byte[]]$original.Clone();$bad[4096]=$bad[4096] -bxor 1
[IO.File]::WriteAllBytes((Join-Path $base 'graph-only.template'),$bad)
Refuse {New-PinnedGraphFromTemplate $mock $guid (Join-Path $root 'corrupt-image')}
$mockUsb=Join-Path $root 'mock-usb'
New-Item -ItemType Directory -Path (Join-Path $mockUsb 'EFI/BOOT') -Force|Out-Null
$oldBoot=Join-Path $mockUsb 'EFI/BOOT/BOOTX64.EFI'
[IO.File]::WriteAllText($oldBoot,'original mock loader')
$oldHash=Get-GraphHash $oldBoot
$receipt=Copy-GraphBoot $mockUsb (Join-Path $out 'GRAPH-ONLY.EFI') $m.EfiSha256 'issue172'
if($receipt.PreviousBootSha256 -cne $oldHash -or (Get-GraphHash $oldBoot) -cne $m.EfiSha256 -or
   (Get-GraphHash (Join-Path $mockUsb ('EFI/BOOT/BEFORE-GRAPH-'+$oldHash+'.EFI'))) -cne $oldHash){throw 'Personalized image mock backup/readback failed.'}
$receipt|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $mockUsb 'RTX3090-UNLOCK/graph-stage.json') -Encoding utf8
Refuse {Copy-GraphBoot $mockUsb (Join-Path $out 'GRAPH-ONLY.EFI') $m.EfiSha256 'issue172'}
if($FreshBuild){
 if((Get-GraphHash $FreshBuild) -cne (Get-GraphHash (Join-Path $out 'GRAPH-ONLY.EFI'))){throw 'Compiler/template byte equivalence failed.'}
 Write-Host 'PASS: exact byte equivalence with independently compiled sample-GUID image.'
}
Write-Host 'PASS: GUID-only bytes/order, source pins, empty/sentinel/existing-output/missing-source/corrupt-image refusal. No staging or boot.'
