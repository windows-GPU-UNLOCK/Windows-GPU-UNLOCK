# Offline shared-engine/build test. Never stage, boot or change firmware policy.
[CmdletBinding()]
param([ValidatePattern('^(?:[a-z][a-z0-9-]{0,63})?$')][string]$Machine,[switch]$PackagedFixture,[string]$Clang='clang',[string]$LldLink='lld-link',[string]$Python='python')
$ErrorActionPreference='Stop'
$requestedConfiguration=$Machine
. (Join-Path $PSScriptRoot 'prepare-graph.ps1') -Clang $Clang -LldLink $LldLink -Python $Python
$selected=$null
if($requestedConfiguration){
 $configuration=Read-GraphConfiguration $requestedConfiguration
 $selected=[ordered]@{Id=$configuration.Id;Scope=$configuration.Scope;Sha256=(Get-GraphHash (Join-Path $PSScriptRoot ('graph-configurations/'+$requestedConfiguration+'.json')))}
}
& (Join-Path $PSScriptRoot 'test-graph-configurations.ps1')
if(!$?){throw 'Configuration tests failed; no boot is requested.'}
& (Join-Path $PSScriptRoot 'test-x99-graph-preparation.ps1')
if(!$?){throw 'Mock staging tests failed; no real media were staged.'}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if($PackagedFixture){
 . (Join-Path $PSScriptRoot 'graph-fixture.ps1')
 & (Join-Path $PSScriptRoot 'test-graph-fixture.ps1')
 if(!$?){throw 'Packaged fixture refusal tests failed.'}
 $built=Join-Path $PSScriptRoot 'fixtures'
 $manifest=Get-Content -LiteralPath (Join-Path $built 'graph-only.manifest.json') -Raw|ConvertFrom-Json
 $pe=Get-Content -LiteralPath (Join-Path $built 'graph-only.pe.json') -Raw|ConvertFrom-Json
 $image=Join-Path $built 'graph-only.fixture'
 $hash=Assert-GraphFixture ([IO.File]::ReadAllBytes($image)) $manifest $repo
 $origin='packaged-fixture';$buildPerformed=$false
}else{
 & (Join-Path $PSScriptRoot 'build-graph-only.ps1') -Fixture -Clang $Clang -LldLink $LldLink -Python $Python
 if(!$?){throw 'Offline fixture build failed.'}
 $built=Join-Path $repo 'internal-boot/boot/build/graph-only'
 $manifest=Get-Content -LiteralPath (Join-Path $built 'manifest.json') -Raw|ConvertFrom-Json
 $pe=Get-Content -LiteralPath (Join-Path $built 'pe-verification.json') -Raw|ConvertFrom-Json
 $image=Join-Path $built 'GRAPH-ONLY.EFI';$hash=Get-GraphHash $image
 $origin='locally-built-fixture';$buildPerformed=$true
}
if($manifest.FixtureOnly -ne $true -or $manifest.CanUnlock -ne $false -or $manifest.CanDetach -ne $false -or
   $manifest.ReadsGpuMmio -ne $false -or $manifest.EfiSha256 -cne $hash -or $pe.sha256 -cne $hash -or
   $pe.machine -cne 'AMD64' -or $pe.subsystem -ne 10 -or $pe.imports -ne 0){throw 'Unexpected fixture/PE verification. Never boot it.'}
$bytes=[IO.File]::ReadAllBytes($image)
$offset=[BitConverter]::ToUInt32($bytes,0x3c)
# PE32+ security directory is file-offset based; presence alone is not trust.
if($offset -gt $bytes.Length-176 -or [BitConverter]::ToUInt32($bytes,$offset) -ne 0x4550 -or
   [BitConverter]::ToUInt16($bytes,$offset+24) -ne 0x20b){throw 'Unexpected PE header.'}
$certificateOffset=[BitConverter]::ToUInt32($bytes,$offset+24+112+4*8)
$certificateSize=[BitConverter]::ToUInt32($bytes,$offset+24+112+4*8+4)
$report=[ordered]@{Test='shared-graph-offline-v3';ImageOrigin=$origin;BuildPerformed=$buildPerformed;SelectedConfiguration=$selected;ConfigurationTests='pass';MockStagingTests='pass';
 FixtureOnly=$true;EfiBytes=$bytes.Length;EfiSha256=$hash;Machine=$pe.machine;Imports=$pe.imports;
 CertificateDirectoryPresent=($certificateOffset -ne 0 -or $certificateSize -ne 0);
 SignatureValidated=$false;FirmwareTrustEstablished=$false;HardwareTested=$false;WriteEligible=$false;
 Next='Offline fixture only: never copy to boot media or execute it. Keep Secure Boot and firmware policy unchanged.'}
$docs=[Environment]::GetFolderPath('MyDocuments');if(!$docs){throw 'Documents folder unavailable.'}
$output=Join-Path $docs ('GPU-Unlock-Offline-'+[guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $output|Out-Null
$path=Join-Path $output 'graph-build-test.json';$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('Return only reviewed '+$path+'. Fixture must NEVER be staged or booted; keep Secure Boot enabled.')
