# Read-only Windows inventory. No tuning, GPU workload, firmware writes or reboot.
param([string]$Captures='C:\GPU-Unlock\Captures',[string]$Results='C:\GPU-Unlock\Results')
$ErrorActionPreference='Stop'
$logs=@(Get-ChildItem -LiteralPath $Captures -File -Filter 'DIAG??.TXT')
if($logs.Count -ne 2){throw 'Expected DIAG00.TXT and DIAG01.TXT in C:\GPU-Unlock\Captures. Send this error.'}
$os=Get-CimInstance Win32_OperatingSystem
$board=Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer,Product
$bios=Get-CimInstance Win32_BIOS | Select-Object Manufacturer,SMBIOSBIOSVersion
$gpu=@(Get-CimInstance Win32_VideoController | ForEach-Object {
 [ordered]@{name=$_.Name;driver_version=$_.DriverVersion;pci_identity=([regex]::Match($_.PNPDeviceID,'VEN_[0-9A-F]{4}&DEV_[0-9A-F]{4}&SUBSYS_[0-9A-F]{8}',[Text.RegularExpressions.RegexOptions]::IgnoreCase).Value)}
})
if(!@($gpu | Where-Object {$_.pci_identity -match 'VEN_10DE&DEV_2204'}).Count){throw 'Expected RTX3090 PCI identity; no test performed'}
$smi=Get-Command nvidia-smi -ErrorAction SilentlyContinue
$smiError=$null;$smiOutput=@()
if($smi){
 try{
  $smiOutput=@(& $smi '--query-gpu=pci.bus_id,name,driver_version,memory.total,pstate,power.limit,clocks.max.sm,clocks.max.memory' '--format=csv' 2>&1 | ForEach-Object {"$_"})
  if($LASTEXITCODE -ne 0){$smiError='nvidia-smi query failed; inspect saved output'}
 }catch{$smiError='nvidia-smi query failed'}
}else{$smiError='nvidia-smi not found; Windows inventory still collected'}
$out=Join-Path $Results ('christian-baseline-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($out)
$report=[ordered]@{schema='christian-windows-baseline-v1';captured_utc=[DateTime]::UtcNow.ToString('o');windows_caption=$os.Caption;windows_build=$os.BuildNumber;last_boot_utc=$os.LastBootUpTime.ToUniversalTime().ToString('o');board=$board;bios=$bios;gpus=$gpu;capture_hashes=@($logs | ForEach-Object {[ordered]@{file=$_.Name;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}});nvidia_smi_error=$smiError;gpu_workload_run=$false;settings_changed=$false;firmware_written=$false;unlock_proven=$false}
[IO.File]::WriteAllText((Join-Path $out 'baseline.json'),($report | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllLines((Join-Path $out 'nvidia-smi.csv'),[string[]]$smiOutput,[Text.UTF8Encoding]::new($false))
$zip=$out+'.zip';Compress-Archive -LiteralPath $out -DestinationPath $zip -ErrorAction Stop
[ordered]@{evidence_zip=$zip;gpu_workload_run=$false;settings_changed=$false;firmware_written=$false;next='Attach this ZIP in the Christian thread. No reboot or EFI test.'} | ConvertTo-Json
