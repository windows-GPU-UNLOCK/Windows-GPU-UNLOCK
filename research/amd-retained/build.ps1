# GPL-2.0-only. Compile-only original B650M retained-AMD experiment. No staging/BCD.
param([Parameter(Mandatory)][string]$Clang,[Parameter(Mandatory)][string]$LldLink,
 [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')][string]$BuildName='amd-retained')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out=Join-Path $repo ('internal-boot/boot/build/'+$BuildName)
if(Test-Path -LiteralPath $out){throw 'Build output exists; preserve it and use a fresh workspace'}
Push-Location -LiteralPath $repo
try {
 $sourcePaths=@(git ls-files -- internal-boot deps research/amd-retained research/profile/probe-manifest.ps1 research/profile/proven.json)
 if($LASTEXITCODE -ne 0){throw 'Source inventory failed'}
 $sourcePaths+=@('internal-boot/local-config.json','internal-boot/boot/platform-config.h','research/amd-retained/build.ps1')
 $sourcePaths=@($sourcePaths | Sort-Object -Unique)
 $sourceBefore=@($sourcePaths | ForEach-Object {[ordered]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
 & ./internal-boot/Build.ps1 -Clang $Clang -LldLink $LldLink
 if(!$?){throw 'Original manual/automatic child contracts failed'}
 foreach($row in $sourceBefore){if((Get-FileHash -LiteralPath $row.Path).Hash.ToLowerInvariant() -cne $row.Sha256){throw 'Source changed while building children'}}
 $sources=@('internal-boot/boot/handoff.c','internal-boot/boot/full-release.c','internal-boot/boot/full-flow.c',
 'internal-boot/boot/diagnostic.c','internal-boot/unlock/checks.c','internal-boot/unlock/sha256.c','internal-boot/efi_runtime.c')
 # Include all tracked inputs in this exact build contract, including headers,
 # scripts, local partition config and both generated child contracts.
 $paths=@($sourcePaths)+@('internal-boot/boot/generated.h','internal-boot/boot/build/automatic/child-contract.h')
 $paths=@($paths | Sort-Object -Unique)
 $before=@($paths | ForEach-Object {[ordered]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant()}})
 [void][IO.Directory]::CreateDirectory($out)
 foreach($mode in @('manual','automatic')) {
  $dir=Join-Path $out $mode;[void][IO.Directory]::CreateDirectory($dir)
  $defines=@('-DGU_FULL_UNLOCK','-DGU_AMD_RETAINED_MULTI_DISPLAY')
  if($mode -eq 'automatic'){$defines+='-DGU_AUTOMATIC_BOOT'}
  $objects=@()
  foreach($source in $sources) {
   $obj=Join-Path $dir ([IO.Path]::GetFileNameWithoutExtension($source)+'.obj')
   & $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fno-builtin -fno-stack-protector -mno-red-zone -fshort-wchar -Os -Wall -Wextra -Werror @defines -I deps/edk2/MdePkg/Include -I deps/edk2/MdePkg/Include/X64 -c $source -o $obj
   if($LASTEXITCODE -ne 0){throw "Wrapper compile failed: $source"};$objects+=$obj
  }
  $efi=Join-Path $dir 'AMD-RETAINED.EFI';$map=Join-Path $dir 'AMD-RETAINED.map'
  & $LldLink /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf "/map:$map" "/out:$efi" @objects
  if($LASTEXITCODE -ne 0){throw 'AMD wrapper link failed'}
  python -I internal-boot/unlock/verify_pe.py $efi $map --output (Join-Path $dir 'pe-verification.json')
  if($LASTEXITCODE -ne 0){throw 'AMD wrapper PE validation failed'}
  $child=if($mode -eq 'automatic'){'internal-boot/unlock/build/experimental/entryLatchedSs1Full/internal/automatic/RTX3090-EXPERIMENTAL-entryLatchedSs1Full-INTERNAL-AUTO.EFI'}else{'internal-boot/unlock/build/experimental/entryLatchedSs1Full/internal/RTX3090-EXPERIMENTAL-entryLatchedSs1Full-INTERNAL.EFI'}
  [ordered]@{Mode=('amd-retained-1-2-rtx-displays-'+$mode);HardwareProfile='ASUS-TUF-B650M-PLUS-WIFI-3057-RTX3090-FE';HardwareTested=$false
   Defines=$defines;EfiSha256=(Get-FileHash -LiteralPath $efi).Hash.ToLowerInvariant();Child=$child;ChildSha256=(Get-FileHash -LiteralPath $child).Hash.ToLowerInvariant()
   BuiltUtc=[DateTime]::UtcNow.ToString('o');Inputs=$before} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding utf8
 }
 foreach($row in $before){if((Get-FileHash -LiteralPath $row.Path).Hash.ToLowerInvariant() -cne $row.Sha256){throw 'Source changed during build'}}
 'AMD-retained manual and automatic pairs built. No installation, boot-setting change or EFI execution.'
}finally{Pop-Location}
