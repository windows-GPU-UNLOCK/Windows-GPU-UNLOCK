# Complete CPU/mock validation. Optional VcVars only initializes the compiler environment.
param([string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python',[string]$VcVars,
 [ValidateSet('issue114','issue173')][string]$FixtureMachine='issue114')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if(Test-Path -LiteralPath (Join-Path $repo 'internal-boot/boot/platform-config.h')){
 throw 'Fixture tests require a fresh source folder; existing platform-config.h is preserved. Do not move a real configuration aside for this test.'
}
if($VcVars){
 $lines=& cmd.exe /d /c "call `"$VcVars`" >nul && set"
 if($LASTEXITCODE -ne 0){throw 'MSVC environment failed.'}
 foreach($line in $lines){if($line -match '^([^=]+)=(.*)$'){[Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process')}}
}
& (Join-Path $PSScriptRoot 'test-resource-preparation.ps1')
if(!$?){throw 'Shared resource mocks failed.'}
& (Join-Path $PSScriptRoot 'test-zotac-preparation.ps1') -Python $Python
if(!$?){throw 'Preparation mocks failed.'}
Push-Location (Join-Path $repo 'internal-boot/boot')
try {
 New-Item -ItemType Directory -Path build/probe-pinned-tests -Force | Out-Null
 $flags=@('-DGU_DIAGNOSTIC_ONLY','-DGU_DIAGNOSTIC_PROBE','-DGU_PROBE_GENERIC')
 $includes=@('-I','../../deps/edk2/MdePkg/Include','-I','../../deps/edk2/MdePkg/Include/X64')
 foreach($test in @('generic','pinned','x570','lenovo','evga','evga-wrong-bus','evga-other-board')){
  $extra=if($test -eq 'pinned'){@('-DGU_PROBE_EXPECTED_ID=0x250410deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x263019daU')}elseif($test -eq 'x570'){@('-DGU_PROBE_EXPECTED_ID=0x220410deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x147d10deU','-DGU_PROBE_BUS=8U')}elseif($test -eq 'lenovo'){@('-DGU_PROBE_EXPECTED_ID=0x250410deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x881d1043U')}else{@()}
  if($test -eq 'evga'){$extra=@('-DGU_PROBE_EXPECTED_ID=0x221610deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x48973842U','-DGU_PROBE_BUS=1U')}
  if($test -eq 'evga-wrong-bus'){$extra=@('-DGU_PROBE_EXPECTED_ID=0x221610deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x48973842U','-DGU_PROBE_BUS=8U')}
  if($test -eq 'evga-other-board'){$extra=@('-DGU_PROBE_EXPECTED_ID=0x221610deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x403f1458U','-DGU_PROBE_BUS=1U')}
  $source=if($test -ne 'generic'){'test_probe_pinned.c'}else{'test_probe_generic.c'}
  if($test -in @('evga-wrong-bus','evga-other-board')){$source='test_probe_research_refusal.c'}
  & $Clang -std=c11 -O1 -Wall -Wextra -Werror -D_CRT_SECURE_NO_WARNINGS @flags @extra @includes $source probe.c ../unlock/sha256.c -o "build/probe-pinned-tests/$test.exe"
  if($LASTEXITCODE -ne 0){throw "Mock compile failed: $test"}
  & "./build/probe-pinned-tests/$test.exe"
  if($LASTEXITCODE -ne 0){throw "Mock test failed: $test"}
 }
 foreach($extra in @(
   @('-DGU_PROBE_EXPECTED_ID=0x250410deU'),
   @('-DGU_PROBE_EXPECTED_ID=0x250410deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x263019daU','-DGU_FULL_UNLOCK'),
   @('-DGU_PROBE_EXPECTED_ID=0x250410deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x263019daU','-DGU_CONSOLE_PREPARE'),
   @('-DGU_PROBE_EXPECTED_ID=0x250410deU','-DGU_PROBE_EXPECTED_SUBSYSTEM=0x263019daU','-DGU_PROBE_AUTO_BUS'))){
  $ErrorActionPreference='Continue'
  $output=& $Clang -target x86_64-pc-windows-msvc -std=c11 -fshort-wchar -fsyntax-only @flags @extra @includes probe.c 2>&1 | Out-String
  $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
  if($code -eq 0 -or $output -notmatch 'Probe identity pins'){throw 'Forbidden pin build was not rejected.'}
 }
 Write-Host 'PASS: missing pin/full-unlock/console-release/auto-bus builds refused.'
} finally {Pop-Location}
# Fixture build uses a mock partition observation, never real disk discovery.
function Get-Partition {[pscustomobject]@{Guid='11111111-2222-3333-4444-555555555555';IsSystem=$true}}
$fixtureDevice='250410de';$fixtureSubsystem='263019da'
if($FixtureMachine -ceq 'issue173'){$fixtureDevice='221610de';$fixtureSubsystem='48973842'}
& (Join-Path $PSScriptRoot 'build-probe.ps1') -WindowsEspGuid 11111111-2222-3333-4444-555555555555 -TargetBus 1 -ExpectedDevice $fixtureDevice -ExpectedSubsystem $fixtureSubsystem -Clang $Clang -LldLink $LldLink -Python $Python
if(!$?){throw 'Pinned fixture build failed.'}
. (Join-Path $PSScriptRoot 'probe-manifest.ps1')
$built=Join-Path $repo 'internal-boot/boot/build/probe-generic'
$manifest=Get-Content (Join-Path $built 'manifest.json') -Raw | ConvertFrom-Json
$image=Join-Path $built 'BOOTX64.EFI'
Assert-GuGenericProbeManifest $repo $manifest $image
foreach($field in @('ExpectedSubsystem','ExpectedSegment','ExpectedDevice')){
 $copy=$manifest | ConvertTo-Json -Depth 8 | ConvertFrom-Json
 if($field -eq 'ExpectedSegment'){$copy.$field=1}else{$copy.$field='00000000'}
 $refused=$false;try{Assert-GuGenericProbeManifest $repo $copy $image}catch{$refused=$true}
 if(!$refused){throw 'Tampered pin manifest accepted.'}
}
Write-Host 'PASS: pinned EFI/PE/source manifest and tampered-pin refusal. Fixture Windows GUID is not bootable; do not stage this test artifact.'
