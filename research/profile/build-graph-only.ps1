# Build files only. Does not stage, register a boot entry, or reboot.
[CmdletBinding(DefaultParameterSetName='Fixture')]
param(
 [Parameter(Mandatory,ParameterSetName='Pinned')][guid]$WindowsEspGuid,
 [Parameter(ParameterSetName='Fixture')][switch]$Fixture,
 [string]$Clang='clang', [string]$LldLink='lld-link', [string]$Python='python'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$boot=Join-Path $repo 'internal-boot/boot'
$out=Join-Path $boot 'build/graph-only'
if($PSCmdlet.ParameterSetName -eq 'Pinned' -and $WindowsEspGuid -eq [guid]::Empty){throw 'Windows ESP GUID cannot be empty.'}
$fixtureBuild=$PSCmdlet.ParameterSetName -eq 'Fixture'
if($fixtureBuild){$WindowsEspGuid=[guid]::Empty}
New-Item -ItemType Directory -Path $out -Force | Out-Null
function FileHash([string]$Path){
 $sha=[Security.Cryptography.SHA256]::Create()
 $stream=[IO.File]::OpenRead([IO.Path]::GetFullPath($Path))
 try {return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
 finally {$stream.Dispose();$sha.Dispose()}
}
function GuidC([guid]$Value){
 $b=$Value.ToByteArray();$tail=($b[8..15] | ForEach-Object {'0x{0:x2}' -f $_}) -join ','
 return ('{{0x{0:x8},0x{1:x4},0x{2:x4},{{{3}}}}}' -f [BitConverter]::ToUInt32($b,0),[BitConverter]::ToUInt16($b,4),[BitConverter]::ToUInt16($b,6),$tail)
}
@(('#define GU_INTERNAL_PARTITION_INITIALIZER '+(GuidC ([guid]::Empty))),
  ('#define GU_WINDOWS_PARTITION_INITIALIZER '+(GuidC $WindowsEspGuid))) |
 Set-Content -LiteralPath (Join-Path $out 'graph-platform-config.h') -Encoding ascii
$sources=@('handoff.c','diagnostic.c','../efi_runtime.c','../unlock/sha256.c')
$defines=@('-DGU_DIAGNOSTIC_ONLY','-DGU_GRAPH_ONLY','-DGU_USB_MEDIA')
Push-Location -LiteralPath $boot
try {
 $objects=@()
 foreach($source in $sources){
  $obj=Join-Path $out ([IO.Path]::GetFileNameWithoutExtension($source)+'.obj')
  & $Clang -target x86_64-pc-windows-msvc -std=c11 -ffreestanding -fno-builtin -fno-stack-protector -mno-red-zone -fshort-wchar -Os -Wall -Wextra -Werror @defines -I $out -I ../../deps/edk2/MdePkg/Include -I ../../deps/edk2/MdePkg/Include/X64 -c $source -o $obj
  if($LASTEXITCODE -ne 0){throw "Compile failed: $source"};$objects+=$obj
 }
 $image=Join-Path $out 'GRAPH-ONLY.EFI';$map=Join-Path $out 'GRAPH-ONLY.map'
 & $LldLink /nologo /nodefaultlib /subsystem:efi_application /entry:efi_main /machine:x64 /base:0 /dynamicbase /nxcompat /timestamp:0 /opt:ref /opt:icf "/map:$map" "/out:$image" @objects
 if($LASTEXITCODE -ne 0){throw 'Graph-only link failed'}
 & $Python -I ../unlock/verify_pe.py $image $map --output (Join-Path $out 'pe-verification.json')
 if($LASTEXITCODE -ne 0){throw 'Graph-only PE verification failed'}
 $rows=@($sources+@('diagnostic.h','media.h','flow.h','../unlock/machine-profile.h','../unlock/gpu-family.h','../unlock/firmware-profile.h') | ForEach-Object {
  [ordered]@{Path=$_;Sha256=(FileHash (Join-Path $boot $_))}
 })
 [ordered]@{Mode='graph-only-build';FixtureOnly=$fixtureBuild;HardwareTested=$false;CanUnlock=$false;CanDetach=$false;ReadsGpuMmio=$false;DumpsProm=$false;DumpsImages=$false;WritesFirmwareVariables=$false;Defines=$defines;Sources=$rows;EfiSha256=(FileHash $image)} |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'manifest.json') -Encoding utf8
 Write-Host 'Graph-only build verified. No media staged or boot requested. Fixture builds must not be booted.'
} finally {Pop-Location}
