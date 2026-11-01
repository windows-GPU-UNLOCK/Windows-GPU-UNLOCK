$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot ('build/christian-baseline-fixture-'+[guid]::NewGuid().ToString('N'))
$captures=Join-Path $root 'captures';[void][IO.Directory]::CreateDirectory($captures)
foreach($name in @('DIAG00.TXT','DIAG01.TXT')){Set-Content -LiteralPath (Join-Path $captures $name) -Value 'fixture'}
$global:christianGpuOk=$true
function Get-CimInstance($ClassName){
 switch($ClassName){
  Win32_OperatingSystem {[pscustomobject]@{Caption='fixture OS';BuildNumber='26200';LastBootUpTime=[DateTime]'2026-11-01T00:00:00Z'}}
  Win32_BaseBoard {[pscustomobject]@{Manufacturer='fixture';Product='board';SerialNumber='DO-NOT-EXPORT'}}
  Win32_BIOS {[pscustomobject]@{Manufacturer='fixture';SMBIOSBIOSVersion='1';SerialNumber='DO-NOT-EXPORT'}}
  Win32_VideoController {[pscustomobject]@{Name='3090';DriverVersion='fixture';PNPDeviceID=$(if($global:christianGpuOk){'PCI\VEN_10DE&DEV_2204&SUBSYS_12341462\PRIVATE-INSTANCE'}else{'PCI\VEN_10DE&DEV_2782&SUBSYS_12341462'})}}
  default {throw 'Unexpected query'}
 }
}
function nvidia-smi {
 if($args.Count -ne 2 -or $args[0] -notlike '--query-gpu=*' -or $args[1] -cne '--format=csv'){throw 'Unexpected NVIDIA command'}
 $global:LASTEXITCODE=0
 'pci.bus_id, name, driver_version';'0000:01:00.0, fixture, 596.49'
}
$entry=Join-Path $PSScriptRoot 'collect-christian-baseline.ps1'
$out=& $entry -Captures $captures -Results (Join-Path $root 'results') | ConvertFrom-Json
if(!(Test-Path -LiteralPath $out.evidence_zip) -or $out.gpu_workload_run -or $out.settings_changed -or $out.firmware_written){throw 'Invalid baseline result'}
$report=Get-ChildItem -LiteralPath (Join-Path $root 'results') -Recurse -Filter baseline.json | Get-Content -Raw
if($report -match 'DO-NOT-EXPORT|PRIVATE-INSTANCE'){throw 'Unnecessary private identity included'}
if(($report | ConvertFrom-Json).capture_hashes.Count -ne 2){throw 'Missing capture hashes'}
$global:christianGpuOk=$false;$blocked=$false
try{& $entry -Captures $captures -Results (Join-Path $root 'wrong-gpu') | Out-Null}catch{$blocked=$true}
if(!$blocked -or (Test-Path -LiteralPath (Join-Path $root 'wrong-gpu'))){throw 'Wrong GPU not refused before output'}
Write-Host 'PASS baseline packaging, query-only NVIDIA arguments, serial/instance exclusion, hashes and wrong-GPU refusal. All hardware queries mocked.'
