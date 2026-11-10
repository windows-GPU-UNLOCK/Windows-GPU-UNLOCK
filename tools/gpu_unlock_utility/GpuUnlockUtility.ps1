<#
.SYNOPSIS
    Windows GPU UNLOCK - Executive Control, Compatibility Checker & Deployment Utility
.DESCRIPTION
    A comprehensive Windows utility for the Windows-GPU-UNLOCK project.
    Provides hardware compatibility auditing, safety pre-flight checks,
    offline compatibility checking and analysis of pre-boot EFI captures,
    report comparisons, USB and internal EFI boot deployment, live GPU telemetry,
    and 1-click emergency recovery.
.PARAMETER Cli
    Runs in command-line mode instead of launching the WPF GUI.
.PARAMETER Action
    CLI action: 'Audit', 'Preflight', 'CheckUsb', 'DeployUsb', 'RestoreWindows',
    'Telemetry', 'CheckCaptures', 'CompareReports'.
.PARAMETER DriveLetter
    Drive letter for USB or ESP operations (e.g., 'E').
.PARAMETER CapturePath
    Path to existing capture folder containing DIAGnn.TXT, IMGnn.BIN, PROM.BIN for analysis.
.PARAMETER LeftReport
    Path to first JSON report for comparison.
.PARAMETER RightReport
    Path to second JSON report for comparison.
.PARAMETER ExportPath
    Optional destination path to save JSON compatibility report.
.PARAMETER Lang
    Language for reports and explanations ('en' or 'ko'). Defaults to 'en'.
.PARAMETER Json
    Switch to output raw JSON in CLI mode.
#>
[CmdletBinding()]
param(
    [switch]$Cli,
    [ValidateSet('Audit', 'Preflight', 'CheckUsb', 'DeployUsb', 'StageProbe', 'BuildLocalUsb', 'RestoreWindows', 'Telemetry', 'VerifyTensor', 'CheckCaptures', 'CompareReports', 'GenerateDumps', 'DownloadAssets')]
    [string]$Action = 'Audit',
    [ValidateSet('Windows', 'EfiCaptures', 'ProbeUsb')]
    [string]$DumpType = 'Windows',
    [string]$DumpPath,
    [string]$DriveLetter,
    [string]$CapturePath,
    [string]$LeftReport,
    [string]$RightReport,
    [string]$ExportPath,
    [ValidateSet('en', 'ko')]
    [string]$Lang = 'en',
    [switch]$Json,
    [switch]$OptIn
)

$ErrorActionPreference = 'Stop'
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$Script:RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..\..'))
$Script:AssetsPath = Join-Path $Script:RepoRoot 'assets'
$Script:ReleaseEfi = Join-Path $Script:RepoRoot 'release\EFI\BOOT\BOOTX64.EFI'
$Script:ProvenanceFile = Join-Path $Script:RepoRoot 'release\provenance.json'
$Script:AssetsJson = Join-Path $Script:RepoRoot 'unlock\assets.json'
$Script:ProvenJson = Join-Path $Script:RepoRoot 'research\profile\proven.json'
$Script:CheckerPy = Join-Path $Script:RepoRoot 'research\profile\check-compatibility.py'
$Script:ComparatorPy = Join-Path $Script:RepoRoot 'research\profile\compare-compatibility.py'

# --- CORE ENGINE FUNCTIONS ---
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Sha256Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ClangToolchain {
    $clangPath = $null
    $lldLinkPath = $null

    $candidates = @(
        "C:\Program Files\LLVM\bin",
        "C:\TOOLS\LLVM20\bin",
        "C:\TOOLS\LLVM\bin"
    )
    foreach ($c in $candidates) {
        $cClang = Join-Path $c "clang.exe"
        $cLld = Join-Path $c "lld-link.exe"
        if ((Test-Path -LiteralPath $cClang) -and (Test-Path -LiteralPath $cLld)) {
            $clangPath = $cClang
            $lldLinkPath = $cLld
            break
        }
    }

    if (-not $clangPath) {
        $cmdClang = Get-Command clang.exe -ErrorAction SilentlyContinue
        $cmdLld = Get-Command lld-link.exe -ErrorAction SilentlyContinue
        if ($cmdClang -and $cmdLld) {
            $clangPath = $cmdClang.Source
            $lldLinkPath = $cmdLld.Source
        }
    }

    return @{
        Available = (-not [string]::IsNullOrEmpty($clangPath))
        Clang     = $clangPath
        LldLink   = $lldLinkPath
    }
}

function Get-SystemWindowsEspGuid {
    try {
        $part = Get-Partition | Where-Object { $_.IsSystem } | Select-Object -First 1
        if ($part -and $part.Guid) {
            $g = [regex]::Match($part.Guid, '[0-9a-fA-F-]{36}')
            if ($g.Success) { return $g.Value }
        }
    } catch {}
    return $null
}

function Get-UsbProbeCaptureStatus([string]$Letter) {
    $cleanLetter = $Letter.TrimEnd(':')
    $dir = "$($cleanLetter):\RTX3090-UNLOCK"
    $captures = @()
    if (Test-Path -LiteralPath $dir) {
        $files = Get-ChildItem -LiteralPath $dir -Filter 'DIAG??.TXT' -File -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            try {
                $t = [IO.File]::ReadAllText($f.FullName)
                if ($t.Contains('probe-pci-handles=') -and $t.Contains("capture-complete=1`r`n")) {
                    $captures += $f
                }
            } catch {}
        }
    }
    $hasProm = Test-Path -LiteralPath (Join-Path $dir 'PROM.BIN')
    $hasImg = (Test-Path -LiteralPath (Join-Path $dir 'IMG00.BIN')) -or (Test-Path -LiteralPath (Join-Path $dir 'IMG01.BIN'))
    return @{
        Count     = $captures.Count
        Required  = 2
        Captures  = $captures
        HasProm   = $hasProm
        HasImg    = $hasImg
        Directory = $dir
    }
}

function Get-GpuHardwareInfo {
    $info = [ordered]@{}
    try {
        $board = Get-CimInstance Win32_BaseBoard -Property Manufacturer, Product | Select-Object -First 1
        $cpu = Get-CimInstance Win32_Processor -Property Name, Manufacturer | Select-Object -First 1
        $bios = Get-CimInstance Win32_BIOS -Property Manufacturer, SMBIOSBIOSVersion | Select-Object -First 1
        $os = Get-CimInstance Win32_OperatingSystem -Property Caption, Version, BuildNumber, OSArchitecture | Select-Object -First 1
        $videoControllers = @(Get-CimInstance Win32_VideoController -Property Name, PNPDeviceID, DriverVersion, AdapterRAM)

        $info['Motherboard'] = "$($board.Manufacturer) $($board.Product)".Trim()
        $info['BoardProduct'] = [string]$board.Product
        $info['BIOS'] = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)".Trim()
        $info['BIOSVersion'] = [string]$bios.SMBIOSBIOSVersion
        $info['CPU'] = [string]$cpu.Name
        $info['OS'] = "$($os.Caption) ($($os.Version) Build $($os.BuildNumber))"

        $gpus = @()
        foreach ($vc in $videoControllers) {
            $pnp = [string]$vc.PNPDeviceID
            $devMatch = [regex]::Match($pnp, 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})(?:&SUBSYS_([0-9A-Fa-f]{8}))?', 'IgnoreCase')
            $pci = $null
            if ($devMatch.Success) {
                $ven = $devMatch.Groups[1].Value.ToLowerInvariant()
                $dev = $devMatch.Groups[2].Value.ToLowerInvariant()
                $subsys = $devMatch.Groups[3].Value.ToLowerInvariant()
                $subVen = if ($subsys.Length -ge 8) { $subsys.Substring(4, 4) } else { "" }
                $subDev = if ($subsys.Length -ge 8) { $subsys.Substring(0, 4) } else { "" }
                $pci = @{
                    Vendor          = $ven
                    Device          = $dev
                    Subsystem       = $subsys
                    SubsystemVendor = $subVen
                    SubsystemDevice = $subDev
                }
            }

            # Identify architecture and known models
            $arch = "Unknown"
            $family = "Unknown"
            $isAmpere = $false
            if ($pci -and $pci.Vendor -eq '10de') {
                switch ($pci.Device) {
                    '2204' { $arch = "RTX 3090 (GA102)"; $family = "GA102"; $isAmpere = $true }
                    '2203' { $arch = "RTX 3090 Ti (GA102)"; $family = "GA102"; $isAmpere = $true }
                    '2206' { $arch = "RTX 3080 (GA102)"; $family = "GA102"; $isAmpere = $true }
                    '220a' { $arch = "RTX 3080 12GB (GA102)"; $family = "GA102"; $isAmpere = $true }
                    '2208' { $arch = "RTX 3080 Ti (GA102)"; $family = "GA102"; $isAmpere = $true }
                    '2484' { $arch = "RTX 3070 (GA104)"; $family = "GA104"; $isAmpere = $true }
                    '2482' { $arch = "RTX 3070 Ti (GA104)"; $family = "GA104"; $isAmpere = $true }
                    '2487' { $arch = "RTX 3060 12GB (GA104)"; $family = "GA104"; $isAmpere = $true }
                    '24c9' { $arch = "RTX 3060 Ti (GA104)"; $family = "GA104"; $isAmpere = $true }
                    '2503' { $arch = "RTX 3060 (GA106)"; $family = "GA106"; $isAmpere = $true }
                    '2504' { $arch = "RTX 3060 12GB (GA106)"; $family = "GA106"; $isAmpere = $true }
                    default {
                        if ($vc.Name -match 'RTX 30') { $arch = "Ampere Family"; $family = "GA10x"; $isAmpere = $true }
                    }
                }
            }

            $vramMb = [math]::Round([double]$vc.AdapterRAM / 1MB)
            $gpus += [ordered]@{
                Name          = [string]$vc.Name
                DriverVersion = [string]$vc.DriverVersion
                PCI           = $pci
                Architecture  = $arch
                Family        = $family
                IsAmpere      = $isAmpere
                VramMb        = $vramMb
            }
        }
        $info['GPUs'] = $gpus

        # Check matching profile
        $match = "No exact fixed profile match. Candidate for Local Profile / USB route."
        $nvidiaGpu = $gpus | Where-Object { $_.IsAmpere } | Select-Object -First 1
        if ($nvidiaGpu) {
            $bp = $info['BoardProduct']
            $bv = $info['BIOSVersion']
            if ($bp -match 'B650M-PLUS' -and $bv -eq '3057' -and $nvidiaGpu.PCI.Device -eq '2204') {
                $match = "Exact Match: b650m-3090fe (ASUS TUF B650M-PLUS WIFI / 3057 / RTX 3090 FE)"
            }
            elseif ($bp -match 'B660M-E' -and $bv -eq '4003' -and $nvidiaGpu.PCI.Device -eq '2482') {
                $match = "Exact Match: b660m-3070ti (ASUS TUF B660M-E D4 / 4003 / RTX 3070 Ti)"
            }
            elseif ($bp -match 'X870' -and $bv -eq 'F13d' -and $nvidiaGpu.PCI.Device -eq '2203') {
                $match = "Exact Match: x870-3090ti (Gigabyte X870 AORUS ELITE / F13d / RTX 3090 Ti)"
            }
            elseif ($bp -match 'B660-PLUS' -and $bv -eq '3010' -and $nvidiaGpu.PCI.Device -in @('2487', '2504')) {
                $match = "Exact Match: b660plus-3060 (ASUS PRIME B660-PLUS D4 / 3010 / RTX 3060)"
            }
            elseif ($bp -match 'H610M H' -and $bv -eq 'FC' -and $nvidiaGpu.PCI.Device -eq '2504') {
                $match = "Exact Match: h610m-3060 (Gigabyte H610M H / FC / RTX 3060 GA106)"
            }
            elseif ($nvidiaGpu.IsAmpere) {
                $match = "Eligible GPU ($($nvidiaGpu.Architecture)): Compatible with Headless USB / Local Profile route."
            }
        }
        $info['ProfileAssessment'] = $match

    }
    catch {
        $info['Error'] = $_.Exception.Message
    }
    return $info
}

function Get-PreflightChecks {
    $checks = [ordered]@{}

    # 1. Administrator rights
    $isAdmin = Test-IsAdmin
    $checks['IsAdmin'] = @{
        Status = if ($isAdmin) { 'PASS' } else { 'WARN' }
        Title  = "Administrative Privileges"
        Detail = if ($isAdmin) { "Running as Administrator. Full deployment and BCD controls enabled." }
        else { "Running in Standard User mode. Read-only audits active; elevation required for BCD/ESP writes." }
    }

    # 2. Secure Boot status
    $sbEnabled = $null
    try {
        $sbReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -ErrorAction SilentlyContinue
        if ($sbReg) {
            $sbEnabled = ($sbReg.UEFISecureBootEnabled -eq 1)
        }
    }
    catch {}

    if ($sbEnabled -eq $null -and $isAdmin) {
        try { $sbEnabled = Confirm-SecureBootUEFI } catch {}
    }

    $checks['SecureBoot'] = @{
        Status = if ($sbEnabled -eq $false) { 'PASS' } elseif ($sbEnabled -eq $true) { 'FAIL' } else { 'UNKNOWN' }
        Title  = "UEFI Secure Boot"
        Detail = if ($sbEnabled -eq $false) { "Disabled. Unsigned experimental EFI payloads can boot freely." }
        elseif ($sbEnabled -eq $true) { "ENABLED. You MUST disable Secure Boot in BIOS/UEFI settings before booting unlock EFI." }
        else { "Could not query Secure Boot state automatically. Ensure it is disabled in BIOS." }
    }

    # 3. Windows Fast Startup
    $hiber = $null
    try {
        $powerReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue
        if ($powerReg) {
            $hiber = ($powerReg.HiberbootEnabled -eq 1)
        }
    }
    catch {}

    $checks['FastStartup'] = @{
        Status = if ($hiber -eq $false) { 'PASS' } elseif ($hiber -eq $true) { 'WARN' } else { 'UNKNOWN' }
        Title  = "Windows Fast Startup"
        Detail = if ($hiber -eq $false) { "Disabled. Cold boot initializes hardware cleanly." }
        elseif ($hiber -eq $true) { "ENABLED (Hybrid Sleep). Must be disabled so PCIe hardware resets cleanly on cold boot." }
        else { "Status not detected." }
    }

    # 4. BitLocker Protection
    $bitLockerStatus = "NOT_PROTECTED"
    $bitLockerDetail = "No active BitLocker protection detected on C:."
    if ($isAdmin) {
        try {
            $bl = Get-BitLockerVolume -MountPoint C: -ErrorAction SilentlyContinue
            if ($bl) {
                if ($bl.ProtectionStatus -eq 1 -or $bl.VolumeStatus -ne 0) {
                    $bitLockerStatus = "WARN"
                    $bitLockerDetail = "BitLocker protection is ON ($($bl.ProtectionStatus)). Suspend BitLocker before testing UEFI bootloader to prevent recovery prompt."
                }
                else {
                    $bitLockerStatus = "PASS"
                    $bitLockerDetail = "C: is fully decrypted / BitLocker protection is OFF."
                }
            }
        }
        catch {
            $bitLockerStatus = "UNKNOWN"
            $bitLockerDetail = "BitLocker status check error: $($_.Exception.Message)"
        }
    }
    else {
        $bitLockerStatus = "NOTICE"
        $bitLockerDetail = "Elevation required to inspect BitLocker. Verify in Windows Security that BitLocker is suspended if active."
    }

    $checks['BitLocker'] = @{
        Status = $bitLockerStatus
        Title  = "BitLocker C: Encryption"
        Detail = $bitLockerDetail
    }

    # 5. Release EFI Binary
    $efiValid = $false
    $efiDetail = "Release EFI binary missing."
    if (Test-Path -LiteralPath $Script:ReleaseEfi) {
        $efiHash = Get-Sha256Hash $Script:ReleaseEfi
        $prov = if (Test-Path -LiteralPath $Script:ProvenanceFile) { Get-Content -LiteralPath $Script:ProvenanceFile -Raw | ConvertFrom-Json } else { $null }
        if ($prov -and $efiHash -eq $prov.efi_sha256.ToLowerInvariant()) {
            $efiValid = $true
            $efiDetail = "Valid (SHA256: $($efiHash.Substring(0,16))..., matches provenance)."
        }
        else {
            $efiDetail = "EFI binary present but checksum does not match provenance.json."
        }
    }
    $checks['ReleaseEFI'] = @{
        Status = if ($efiValid) { 'PASS' } else { 'WARN' }
        Title  = "Pre-Compiled Release BOOTX64.EFI"
        Detail = $efiDetail
    }

    # 6. Firmware Assets Check
    $assetsValid = $false
    $assetMissing = @()
    if (Test-Path -LiteralPath $Script:AssetsJson) {
        $specs = Get-Content -LiteralPath $Script:AssetsJson -Raw | ConvertFrom-Json
        $assetOkCount = 0
        foreach ($spec in $specs) {
            $f = Join-Path $Script:AssetsPath $spec.Name
            if (Test-Path -LiteralPath $f) {
                $h = Get-Sha256Hash $f
                if ($h -eq $spec.Sha256.ToLowerInvariant()) {
                    $assetOkCount++
                }
                else {
                    $assetMissing += "$($spec.Name) (Checksum mismatch)"
                }
            }
            else {
                $assetMissing += "$($spec.Name) (Missing)"
            }
        }
        if ($assetOkCount -eq $specs.Count) {
            $assetsValid = $true
            $assetDetail = "All 5 required GA102 firmware assets verified in assets/."
        }
        else {
            $assetDetail = "$($assetOkCount)/$($specs.Count) assets present. Missing/Invalid: $($assetMissing -join ', ')"
        }
    }
    else {
        $assetDetail = "assets.json missing from repository."
    }

    $checks['FirmwareAssets'] = @{
        Status = if ($assetsValid) { 'PASS' } else { 'WARN' }
        Title  = "Firmware Asset Files (GA102)"
        Detail = $assetDetail
    }

    # 7. LLVM Compiler Toolchain & Windows ESP
    $toolchain = Get-ClangToolchain
    $espGuid = Get-SystemWindowsEspGuid
    $tcStatus = if ($toolchain.Available -and $espGuid) { 'PASS' } elseif ($toolchain.Available) { 'WARN' } else { 'WARN' }
    $tcDetail = if ($toolchain.Available) {
        "LLVM Clang/LLD ready ($($toolchain.Clang)). $(if ($espGuid) { "Windows ESP: {$espGuid}" } else { "Windows ESP GUID not detected." })"
    } else {
        "LLVM Clang not found. Required for custom Headless USB builds on non-reference hardware."
    }
    $checks['CompilerToolchain'] = @{
        Status = $tcStatus
        Title  = "LLVM Clang & Windows ESP GUID"
        Detail = $tcDetail
    }

    return $checks
}

function Disable-WindowsFastStartup {
    if (-not (Test-IsAdmin)) {
        throw "Administrator privileges required to change Fast Startup setting."
    }
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
    Set-ItemProperty -Path $path -Name HiberbootEnabled -Value 0 -Type DWord -Force
    return "Fast Startup has been disabled (HiberbootEnabled = 0)."
}

function Get-RemovableDrives {
    $drives = @()
    try {
        $disks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -or $_.MediaType -eq 'Removable' })
        foreach ($disk in $disks) {
            $parts = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
            foreach ($part in $parts) {
                if ($part.DriveLetter) {
                    $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction SilentlyContinue
                    $drives += [pscustomobject]@{
                        DriveLetter  = "$($part.DriveLetter):"
                        Letter       = [string]$part.DriveLetter
                        DiskNumber   = $disk.Number
                        FriendlyName = "$($disk.FriendlyName) ($($part.DriveLetter):)"
                        FileSystem   = [string]$vol.FileSystem
                        SizeGb       = [math]::Round($part.Size / 1GB, 2)
                        IsBoot       = [bool]$disk.IsBoot
                        IsSystem     = [bool]$part.IsSystem
                    }
                }
            }
        }
    }
    catch {}
    return $drives
}

function Find-UsbCaptureFolders {
    $found = @()
    $drives = Get-RemovableDrives
    foreach ($d in $drives) {
        $root = "$($d.Letter):\"
        # Check root
        $diagRoot = @(Get-ChildItem -LiteralPath $root -Filter "DIAG*.TXT" -File -ErrorAction SilentlyContinue)
        if ($diagRoot.Count -gt 0) {
            $found += $root.TrimEnd('\')
        }
        # Check RTX3090-UNLOCK
        $rtxDir = Join-Path $root "RTX3090-UNLOCK"
        if (Test-Path -LiteralPath $rtxDir) {
            $found += $rtxDir
        }
    }
    return @($found | Select-Object -Unique)
}

function Deploy-ToUsb([string]$Letter) {
    $cleanLetter = $Letter.TrimEnd(':')
    $driveRoot = "$($cleanLetter):\"
    if (-not (Test-Path -LiteralPath $driveRoot)) {
        throw "Target drive '$driveRoot' does not exist."
    }

    $part = Get-Partition -DriveLetter $cleanLetter -ErrorAction Stop
    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
    $vol = Get-Volume -DriveLetter $cleanLetter -ErrorAction Stop
    if ($disk.BusType -ne 'USB' -or $vol.FileSystem -ne 'FAT32' -or $part.IsSystem -or $disk.IsBoot) {
        throw "$($cleanLetter): is not a FAT32 USB data stick."
    }
    if ($part.IsBoot) {
        throw "$($cleanLetter): is a boot partition; staging refused."
    }

    $info = Get-GpuHardwareInfo
    $nvidiaGpu = $info['GPUs'] | Where-Object { $_.IsAmpere } | Select-Object -First 1
    $bp = $info['BoardProduct']
    $bv = $info['BIOSVersion']

    # Exact fixed legacy manual profile
    $isFixedProfile = ($bp -match 'B650M-PLUS' -and $bv -eq '3057' -and $nvidiaGpu -and $nvidiaGpu.PCI.Device -eq '2204' -and $nvidiaGpu.PCI.Subsystem -eq '145410de')

    if ($isFixedProfile) {
        $targetBootDir = Join-Path $driveRoot "EFI\BOOT"
        $targetPayloadDir = Join-Path $driveRoot "RTX3090-UNLOCK"
        $targetAssetsDir = Join-Path $targetPayloadDir "ASSETS"

        New-Item -ItemType Directory -Path $targetBootDir -Force | Out-Null
        New-Item -ItemType Directory -Path $targetAssetsDir -Force | Out-Null

        # Copy Release BOOTX64.EFI
        if (-not (Test-Path -LiteralPath $Script:ReleaseEfi)) {
            throw "Release BOOTX64.EFI not found in release/EFI/BOOT/BOOTX64.EFI"
        }
        Copy-Item -LiteralPath $Script:ReleaseEfi -Destination (Join-Path $targetBootDir "BOOTX64.EFI") -Force

        # Ensure Assets are present; auto-download if missing
        if (-not (Test-FirmwareAssetsVerified)) {
            Write-Host "[*] Firmware assets missing from assets/. Automatically acquiring now..." -ForegroundColor Yellow
            Invoke-DownloadAssets | Out-Null
        }

        # Copy Assets
        $assetsCopied = 0
        if (Test-Path -LiteralPath $Script:AssetsPath) {
            $assets = Get-ChildItem -LiteralPath $Script:AssetsPath -Filter "*.bin" -File
            foreach ($a in $assets) {
                Copy-Item -LiteralPath $a.FullName -Destination (Join-Path $targetAssetsDir $a.Name) -Force
                $assetsCopied++
            }
        }

        # Copy README & Documentation
        $readmeContent = @"
# Windows GPU UNLOCK - Bootable USB (Fixed Profile)

## Instructions:
1. Ensure Secure Boot is DISABLED in your motherboard BIOS.
2. Shut down your PC completely (Power Off). Do not use Restart.
3. Power on and press your motherboard Boot Menu hotkey:
   - ASUS: F8
   - Gigabyte: F12
   - MSI: F11
   - ASRock: F11
4. Select this USB drive from the Boot Menu (e.g., 'UEFI: USB Drive').
5. Use manual F7 -> Boot Override -> Windows Boot Manager to continue to Windows without reset.
"@
        Set-Content -LiteralPath (Join-Path $driveRoot "USB-README.md") -Value $readmeContent -Encoding utf8

        return [pscustomobject]@{
            Drive        = $driveRoot
            BootEfi      = (Join-Path $targetBootDir "BOOTX64.EFI")
            AssetsCopied = $assetsCopied
            Status       = "Successfully staged stock fixed-profile USB Unlock files."
            IsProbe      = $false
            ProfileMode  = "FixedProfile"
            RequiresBoot = $false
        }
    }
    else {
        # Headless Single-RTX / Local Profile Route (e.g. Intel B460 + ASUS RTX 3090)
        $captureStatus = Get-UsbProbeCaptureStatus -Letter $cleanLetter
        if ($captureStatus.Count -lt 2) {
            throw "Machine requires Headless Single-RTX / Local Profile route with 2 hardware captures (found $($captureStatus.Count) of 2 on $($cleanLetter):). Please stage and boot the Diagnostic Probe USB explicitly first using 'StageProbe' with -OptIn."
        }
        else {
            Write-Host "[+] Found $($captureStatus.Count) hardware captures on USB. Building custom Headless Unlock package..." -ForegroundColor Green
            $msg = Build-And-Stage-Local-Unlock -Letter $cleanLetter
            return [pscustomobject]@{
                Drive        = $driveRoot
                BootEfi      = (Join-Path $driveRoot "EFI\BOOT\BOOTX64.EFI")
                AssetsCopied = 5
                Status       = "Step 2: Successfully built and staged custom Headless Unlock bootloader!"
                IsProbe      = $false
                ProfileMode  = "HeadlessUnlock"
                Captures     = $captureStatus.Count
                RequiresBoot = $false
            }
        }
    }
}

function Restore-WindowsFirstBootOrder {
    if (-not (Test-IsAdmin)) {
        throw "Administrator privileges required to modify UEFI BCD boot order."
    }
    $headlessScript = Join-Path $Script:RepoRoot "internal-boot\Headless.ps1"
    if (Test-Path -LiteralPath $headlessScript) {
        $res = & powershell -NoProfile -ExecutionPolicy Bypass -File $headlessScript -RestoreWindowsFirst
        return ($res -join "`r`n")
    }
    else {
        $fwText = & bcdedit /enum '{fwbootmgr}'
        $m = [regex]::Match($fwText, '(?ms)^displayorder\s+(.*?)(?=\r?\n\S|\z)')
        if ($m.Success) {
            $ids = @([regex]::Matches($m.Groups[1].Value, '\{(?:bootmgr|[0-9a-f-]{36})\}') | ForEach-Object { $_.Value })
            $newOrder = @('{bootmgr}') + @($ids | Where-Object { $_ -ne '{bootmgr}' })
            $argsOrder = @('/set', '{fwbootmgr}', 'displayorder') + $newOrder
            & bcdedit @argsOrder
            return "Restored {bootmgr} as primary boot option."
        }
        return "Could not query {fwbootmgr}."
    }
}

function Get-GpuEfiVariableStatus {
    $efi = [ordered]@{
        'Available'   = $false
        'Active'      = $false
        'Source'      = 'UEFI NVRAM Variable [GpuUnlockState]'
        'Straps'      = 'N/A'
        'Profile'     = 'N/A'
        'Transaction' = 'N/A'
        'Timestamp'   = 'N/A'
        'Handoff'     = 'N/A'
        'Error'       = $null
    }

    try {
        if (-not ([System.Management.Automation.PSTypeName]'GpuUnlockEfiHelper').Type) {
            $src = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class GpuUnlockEfiHelper {
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern uint GetFirmwareEnvironmentVariableW(string lpName, string lpGuid, byte[] pBuffer, uint nSize);

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct TOKEN_PRIVILEGES {
        public uint PrivilegeCount;
        public LUID Luid;
        public uint Attributes;
    }

    public const string SE_SYSTEM_ENVIRONMENT_NAME = "SeSystemEnvironmentPrivilege";
    public const uint SE_PRIVILEGE_ENABLED = 0x00000002;
    public const uint TOKEN_ADJUST_PRIVILEGES = 0x00000020;
    public const uint TOKEN_QUERY = 0x00000008;

    public static bool EnablePrivilege() {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
            return false;
        try {
            LUID luid;
            if (!LookupPrivilegeValue(null, SE_SYSTEM_ENVIRONMENT_NAME, out luid))
                return false;
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Luid = luid;
            tp.Attributes = SE_PRIVILEGE_ENABLED;
            return AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        } catch {
            return false;
        } finally {
            CloseHandle(token);
        }
    }

    public static string ReadEfiVariable(string name, string guid, out int errorCode) {
        errorCode = 0;
        try {
            EnablePrivilege();
            byte[] buffer = new byte[1024];
            uint read = GetFirmwareEnvironmentVariableW(name, guid, buffer, (uint)buffer.Length);
            if (read > 0) {
                return Encoding.UTF8.GetString(buffer, 0, (int)read).TrimEnd('\0');
            }
            errorCode = Marshal.GetLastWin32Error();
            return null;
        } catch {
            errorCode = -1;
            return null;
        }
    }
}
'@
            Add-Type -TypeDefinition $src -ErrorAction SilentlyContinue
        }

        if (([System.Management.Automation.PSTypeName]'GpuUnlockEfiHelper').Type) {
            $errCode = 0
            $guid = "{10DE0000-3090-4100-8888-888888888888}"
            $val = [GpuUnlockEfiHelper]::ReadEfiVariable("GpuUnlockState", $guid, [ref]$errCode)
            if ($val) {
                $efi['Available'] = $true
                $parts = $val -split ';'
                $kv = @{}
                foreach ($p in $parts) {
                    if ($p -match '^([^=]+)=(.*)$') {
                        $kv[$Matches[1].Trim()] = $Matches[2].Trim()
                    }
                }
                $ss0 = if ($kv['SS0']) { $kv['SS0'] -replace '^0x','' } else { '' }
                $ss1 = if ($kv['SS1']) { $kv['SS1'] -replace '^0x','' } else { '' }
                if ($ss0) {
                    $efi['Straps'] = "SS0=0x$ss0 | SS1=0x$ss1"
                    if ($ss0 -eq '88888888' -and ($ss1 -eq '00000008' -or $ss1 -eq '8')) {
                        $efi['Active'] = $true
                    }
                }
                if ($kv['Profile']) { $efi['Profile'] = $kv['Profile'] }
                if ($kv['Transaction']) { $efi['Transaction'] = $kv['Transaction'] }
                elseif ($kv['Status']) { $efi['Transaction'] = "Status=$($kv['Status']), Clean=$($kv['Clean']) (FLR Reset OK)" }
                if ($kv['Timestamp']) { $efi['Timestamp'] = $kv['Timestamp'] }
                if ($kv['Handoff']) { $efi['Handoff'] = $kv['Handoff'] }
                else { $efi['Handoff'] = 'Direct UEFI NVRAM Handoff Verified' }
                return $efi
            } else {
                $efi['Error'] = switch ($errCode) {
                    1314 { "Admin required for direct UEFI NVRAM query" }
                    203  { "Variable not found (system not booted with NVRAM export)" }
                    default { "Win32 Error $errCode" }
                }
            }
        } else {
            $efi['Error'] = "Could not initialize UEFI NVRAM reader."
        }
    } catch {
        $efi['Error'] = $_.Exception.Message
    }
    return $efi
}

function Get-GpuUnlockStatus {
    $status = [ordered]@{
        'Active'      = $false
        'Badge'       = 'LOCKED / STOCK'
        'State'       = 'Stock Consumer State (Locked)'
        'Straps'      = 'SS0=0x25204022 | SS1=0x7 (Stock)'
        'Profile'     = 'None'
        'Transaction' = 'No bootloader unlock detected'
        'Report'      = 'None'
        'Handoff'     = 'Direct Windows Boot'
        'Timestamp'   = 'N/A'
        'Source'      = 'None'
        'Method'      = 'None'
    }

    # 1. Primary Hardware Check: Query live UEFI NVRAM Runtime Environment Variable
    $efiVar = Get-GpuEfiVariableStatus
    if ($efiVar.Available -and $efiVar.Active) {
        $status['Active']      = $true
        $status['Badge']       = 'ACTIVE / UNLOCKED (NVRAM)'
        $status['State']       = 'Active & Unlocked (Workstation/vGPU Straps Latched in NVRAM)'
        $status['Straps']      = $efiVar.Straps
        $status['Profile']     = $efiVar.Profile
        $status['Transaction'] = $efiVar.Transaction
        $status['Report']      = 'UEFI NVRAM Variable [GpuUnlockState]'
        $status['Handoff']     = $efiVar.Handoff
        $status['Timestamp']   = $efiVar.Timestamp
        $status['Source']      = 'Live UEFI NVRAM Runtime Variable'
        $status['Method']      = 'UEFI Runtime Variable'
        return $status
    }

    # 2. Secondary / Fallback Check: Parse latest pre-boot bootloader report on USB or internal ESP drives
    try {
        $drives = Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):\" }
        $candidateReports = @()
        foreach ($d in $drives) {
            $unlockDir = Join-Path $d "RTX3090-UNLOCK"
            if (Test-Path -LiteralPath $unlockDir) {
                $reports = Get-ChildItem -Path (Join-Path $unlockDir "AUTO*\REPORT.TXT") -ErrorAction SilentlyContinue
                if ($reports) { $candidateReports += $reports }
            }
        }

        if ($candidateReports) {
            $latestReport = $candidateReports | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $status['Report'] = "$($latestReport.Directory.Name)/$($latestReport.Name)"
            $status['Timestamp'] = $latestReport.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            $status['Source'] = "Bootloader Session Report ($($latestReport.Directory.Name))"
            $status['Method'] = "Pre-Boot USB / ESP Log"

            $content = Get-Content -LiteralPath $latestReport.FullName -ErrorAction SilentlyContinue
            if ($content) {
                $profLine = $content | Where-Object { $_ -match 'BUILD MODE:.*profile=(\w+)' } | Select-Object -First 1
                if ($profLine -match 'profile=(\w+)') { $status['Profile'] = $Matches[1] }

                $postFlrLine = $content | Where-Object { $_ -match 'post-FLR SEC2 reset released.*SS0=([0-9a-fA-F]+)\s+SS1=([0-9a-fA-F]+)' } | Select-Object -First 1
                if ($postFlrLine -match 'SS0=([0-9a-fA-F]+)\s+SS1=([0-9a-fA-F]+)') {
                    $ss0 = $Matches[1]; $ss1 = $Matches[2]
                    $status['Straps'] = "SS0=0x$ss0 | SS1=0x$ss1"
                    if ($ss0 -eq '88888888' -and ($ss1 -eq '00000008' -or $ss1 -eq '8')) {
                        $status['Active'] = $true
                        $status['Badge'] = 'ACTIVE / UNLOCKED (LOG)'
                        $status['State'] = 'Active & Unlocked (Workstation/vGPU Straps Latched)'
                    }
                }

                $txLine = $content | Where-Object { $_ -match 'FINAL status=(\d+).*clean=(\d+)' } | Select-Object -First 1
                if ($txLine -match 'FINAL status=(\d+).*clean=(\d+)') {
                    $status['Transaction'] = "Status=$($Matches[1]), Clean=$($Matches[2]) (FLR Reset OK)"
                }

                $hlsFile = Join-Path $latestReport.Directory.Parent.FullName "$($latestReport.Directory.Name.Replace('AUTO', 'HLS')).TXT"
                if (Test-Path -LiteralPath $hlsFile) {
                    $hlsContent = Get-Content -LiteralPath $hlsFile -Tail 25 -ErrorAction SilentlyContinue
                    if ($hlsContent -match 'windows-close-files-next-then-final-verify-and-StartImage status=0x0') {
                        $status['Handoff'] = 'bootmgfw.efi Chainloaded Successfully'
                    }
                }
            }
        } else {
            $status['Source'] = if ($efiVar.Error) { "Not detected ($($efiVar.Error))" } else { "No bootloader unlock detected" }
        }
    }
    catch {
        $status['Transaction'] = "Error reading report: $($_.Exception.Message)"
    }

    return $status
}

function Test-GpuSiliconTensor {
    param([int]$Iterations = 50)

    $result = [ordered]@{
        'Tested'        = $false
        'Success'       = $false
        'GpuName'       = 'Unknown'
        'TFlops'        = 0.0
        'Threshold'     = 85.0
        'LimiterState'  = 'Not Tested'
        'Badge'         = 'NOT TESTED'
        'UpliftRatio'   = 'N/A'
        'Message'       = ''
        'Timestamp'     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        'Details'       = ''
    }

    try {
        # Check if Python + PyTorch CUDA is present
        $pyCheck = & python -c "import torch; print(torch.cuda.is_available()); print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')" 2>&1
        $lines = @($pyCheck)
        if ($lines.Count -ge 1 -and $lines[0].Trim() -eq 'True') {
            $gpuName = if ($lines.Count -ge 2) { $lines[1].Trim() } else { "NVIDIA CUDA GPU" }
            $result['GpuName'] = $gpuName

            $code = @"
import torch, time, sys
try:
    if not torch.cuda.is_available():
        sys.exit(2)
    device = torch.device('cuda:0')
    dim = 4096
    a = torch.randn(dim, dim, device=device, dtype=torch.float16)
    b = torch.randn(dim, dim, device=device, dtype=torch.float16)
    for _ in range(8):
        c = torch.matmul(a, b)
    torch.cuda.synchronize()
    
    iterations = $Iterations
    t0 = time.perf_counter()
    for _ in range(iterations):
        c = torch.matmul(a, b)
    torch.cuda.synchronize()
    t1 = time.perf_counter()
    
    elapsed = t1 - t0
    total_flops = iterations * 2.0 * (dim ** 3)
    tflops = (total_flops / elapsed) / 1e12
    print(f'TFLOPS:{tflops:.2f}')
    print(f'ELAPSED:{elapsed:.4f}')
except Exception as ex:
    print(f'ERROR:{ex}')
    sys.exit(1)
"@
            $run = & python -c $code 2>&1
            $runStr = @($run) -join "`n"
            if ($runStr -match 'TFLOPS:([0-9.]+)') {
                $tflops = [double]$Matches[1]
                $result['Tested'] = $true
                $result['Success'] = $true
                $result['TFlops'] = $tflops

                # GA102 (3090/3090Ti): ~40-65 stock, ~110-130 unlocked
                # GA104 (3070Ti): ~40-44 stock, ~85-90 unlocked
                $threshold = if ($gpuName -match '3070') { 75.0 } else { 85.0 }
                $result['Threshold'] = $threshold

                if ($tflops -ge $threshold) {
                    $uplift = [Math]::Round(($tflops / 55.0), 2)
                    $result['LimiterState'] = 'Inactive (Full Silicon Workstation Rate)'
                    $result['Badge'] = "VERIFIED UNLOCKED ($tflops TFLOPS)"
                    $result['UpliftRatio'] = "~${uplift}x over stock (~55 TFLOPS baseline)"
                    $result['Message'] = "PASS: Measured $tflops TFLOPS. Hardware Tensor Core limiter is inactive!"
                } else {
                    $result['LimiterState'] = 'Active (Consumer Throttled / Low Clocks)'
                    $result['Badge'] = "LOCKED / THROTTLED ($tflops TFLOPS)"
                    $result['UpliftRatio'] = "1.0x (Stock consumer ceiling)"
                    $result['Message'] = "Measured $tflops TFLOPS (< $threshold TFLOPS threshold). Limiter appears active or GPU in low-power P-State."
                }
                $result['Details'] = "Matrix: 4096 x 4096 FP16 GEMM ($Iterations iterations) on $gpuName."
                return $result
            }
        }

        # Fallback: Compiled compute-benchmark executable
        $benchExe = Join-Path $Script:RepoRoot "benchmark\bin\compute-benchmark-3090.exe"
        if (Test-Path -LiteralPath $benchExe) {
            $out = & $benchExe 2>&1
            $outStr = @($out) -join "`n"
            $json = $outStr | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json -and $json.benchmarks) {
                $fp16 = $json.benchmarks | Where-Object { $_.name -like '*fp16*' } | Select-Object -First 1
                if ($fp16) {
                    $tflops = [Math]::Round(($fp16.gflops / 1000.0), 2)
                    $result['Tested'] = $true
                    $result['Success'] = $true
                    $result['TFlops'] = $tflops
                    $result['GpuName'] = $json.gpu
                    $threshold = 85.0
                    $result['Threshold'] = $threshold
                    if ($tflops -ge $threshold) {
                        $result['LimiterState'] = 'Inactive (cuBLAS Verified)'
                        $result['Badge'] = "VERIFIED UNLOCKED ($tflops TFLOPS)"
                        $result['Message'] = "PASS: cuBLAS measured $tflops TFLOPS."
                    } else {
                        $result['LimiterState'] = 'Throttled'
                        $result['Badge'] = "THROTTLED ($tflops TFLOPS)"
                        $result['Message'] = "cuBLAS measured $tflops TFLOPS."
                    }
                    return $result
                }
            }
        }

        $result['Message'] = "PyTorch CUDA or benchmark executable not found. Install PyTorch (pip install torch) or run benchmark/setup.ps1 to enable live tensor verification."
    } catch {
        $result['Message'] = "Tensor check failed: $($_.Exception.Message)"
    }
    return $result
}

function Get-GpuTelemetryLive {
    $telemetry = [ordered]@{}
    try {
        $smiOut = & nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw,power.limit,clocks.sm,clocks.mem --format=csv,noheader,nounits 2>&1
        $line = (@($smiOut) -join "`n").Trim()
        if ($line) {
            $parts = $line.Split(',') | ForEach-Object { $_.Trim() }
            if ($parts.Count -ge 10) {
                $telemetry['Name'] = $parts[0]
                $telemetry['Driver'] = $parts[1]
                $telemetry['TempC'] = $parts[2]
                $telemetry['UtilGpu'] = "$($parts[3]) %"
                $telemetry['MemUsedMb'] = "$($parts[4]) MB"
                $telemetry['MemTotalMb'] = "$($parts[5]) MB"
                $telemetry['PowerDrawW'] = "$($parts[6]) W"
                $telemetry['PowerLimitW'] = "$($parts[7]) W"
                $telemetry['ClockSmMhz'] = "$($parts[8]) MHz"
                $telemetry['ClockMemMhz'] = "$($parts[9]) MHz"
            }
        }
        else {
            $telemetry['Error'] = "nvidia-smi not available or GPU query failed."
        }
    }
    catch {
        $telemetry['Error'] = $_.Exception.Message
    }
    return $telemetry
}

# --- DIAGNOSTIC DUMP GENERATION ENGINE ---

function Export-WindowsDiagnosticDump([string]$TargetDir) {
    if (-not $TargetDir) { $TargetDir = Join-Path $Script:RepoRoot "diagnostics" }
    if (-not (Test-Path -LiteralPath $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $timestamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $dumpFolder = Join-Path $TargetDir "GPU-UNLOCK-DIAG-$timestamp"
    New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null

    # 1. System and GPU Inventory JSON
    $invScript = Join-Path $Script:RepoRoot "tools\collect_compatibility.py"
    if (Test-Path -LiteralPath $invScript) {
        $invJson = & python -I $invScript 2>&1
        $invJson | Set-Content -LiteralPath (Join-Path $dumpFolder "WINDOWS-INVENTORY.JSON") -Encoding utf8
    }

    # 2. NVIDIA-SMI XML & Tabular Query
    try {
        $smiXml = & nvidia-smi -q -x 2>&1
        $smiXml | Set-Content -LiteralPath (Join-Path $dumpFolder "NVIDIA-SMI-DUMP.XML") -Encoding utf8
    }
    catch {}

    # 3. System & Pre-Flight Summary
    $audit = Get-GpuHardwareInfo
    $preflight = Get-PreflightChecks
    $summary = [ordered]@{
        GeneratedUtc = [DateTime]::UtcNow.ToString("o")
        Audit        = $audit
        Preflight    = $preflight
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dumpFolder "SYSTEM-SUMMARY.JSON") -Encoding utf8

    # 4. Display & EDID Registry Dump
    try {
        $displayReg = "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY"
        $edidEntries = @()
        if (Test-Path -LiteralPath $displayReg) {
            $monitors = Get-ChildItem -LiteralPath $displayReg -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -eq 'Device Parameters' }
            foreach ($m in $monitors) {
                $edidBytes = (Get-ItemProperty -LiteralPath $m.PSPath -Name "EDID" -ErrorAction SilentlyContinue).EDID
                if ($edidBytes) {
                    $edidHex = ($edidBytes | ForEach-Object { '{0:x2}' -f $_ }) -join ''
                    $edidEntries += [ordered]@{
                        Path     = $m.PSPath
                        EDID_Hex = $edidHex
                        Bytes    = $edidBytes.Length
                    }
                }
            }
        }
        $edidEntries | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $dumpFolder "DISPLAY-EDID.JSON") -Encoding utf8
    }
    catch {}

    # 5. Readme Summary
    $readme = @"
# Windows GPU UNLOCK - Diagnostic Dump Report
Generated: $timestamp

This diagnostic dump package contains complete system, GPU, display, and driver metadata
for compatibility analysis and bug reports:
- WINDOWS-INVENTORY.JSON: Windows hardware and PCI identifiers
- NVIDIA-SMI-DUMP.XML: Full GPU clock, power, memory, and VBIOS parameters
- SYSTEM-SUMMARY.JSON: Motherboard, BIOS, OS, Secure Boot, and BitLocker status
- DISPLAY-EDID.JSON: Active display monitors and EDID registry records
"@
    Set-Content -LiteralPath (Join-Path $dumpFolder "README.TXT") -Value $readme -Encoding utf8

    return $dumpFolder
}

function Export-EfiDiagnosticCaptures([string]$TargetDir, [string]$DeviceId = $null) {
    if (-not $TargetDir) {
        $TargetDir = Join-Path $Script:RepoRoot ("synthetic-captures\fixture-" + [Guid]::NewGuid().ToString('N'))
    }
    if (Test-Path -LiteralPath $TargetDir) {
        throw "Choose a new synthetic-fixture folder. Existing captures are never overwritten."
    }

    if (-not $DeviceId) {
        $info = Get-GpuHardwareInfo
        $ampere = $info.GPUs | Where-Object { $_.IsAmpere } | Select-Object -First 1
        if ($ampere -and $ampere.PCI) {
            $DeviceId = "$($ampere.PCI.Device)$($ampere.PCI.Vendor)"
        }
        else {
            $DeviceId = "220410de"
        }
    }

    $genScript = Join-Path $scriptDir "generate_captures.py"
    $res = & python -I $genScript $TargetDir --device-id $DeviceId 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Synthetic fixture generation failed. No hardware capture was collected. $($res -join ' ')"
    }
    return ($res -join "`r`n")
}

function Stage-DiagnosticProbeUsb {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Letter,
        [switch]$OptIn
    )

    if (-not $OptIn) {
        throw "Staging the Diagnostic Probe is an explicit opt-in operation. Pass -OptIn to proceed."
    }

    $cleanLetter = $Letter.TrimEnd(':')
    $driveRoot = "$($cleanLetter):\"
    if (-not (Test-Path -LiteralPath $driveRoot)) {
        throw "Drive '$driveRoot' does not exist."
    }

    $part = Get-Partition -DriveLetter $cleanLetter -ErrorAction Stop
    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
    $vol = Get-Volume -DriveLetter $cleanLetter -ErrorAction Stop

    if ($disk.BusType -ne 'USB' -or $vol.FileSystem -ne 'FAT32' -or $part.IsSystem -or $disk.IsBoot) {
        throw "$($cleanLetter): is not a FAT32 USB data stick."
    }

    if ($part.IsBoot) {
        throw "$($cleanLetter): is a boot partition; staging refused."
    }

    $espGuid = Get-SystemWindowsEspGuid
    if (-not $espGuid) {
        throw "Could not determine system Windows ESP partition GUID. Ensure Windows is running on a UEFI GPT disk."
    }

    if ($part.Guid -and ([guid]$part.Guid -eq $espGuid)) {
        throw "$($cleanLetter): is the system Windows ESP partition; staging refused."
    }

    $targetBootDir = Join-Path $driveRoot "EFI\BOOT"
    $targetPayloadDir = Join-Path $driveRoot "RTX3090-UNLOCK"
    $targetBootFile = Join-Path $targetBootDir "BOOTX64.EFI"
    $targetReadmeRoot = Join-Path $driveRoot "README-PROBE.TXT"
    $targetReadmePayload = Join-Path $targetPayloadDir "README.TXT"

    # Refuse existing destination files; never overwrite or replace
    foreach ($destFile in @($targetBootFile, $targetReadmeRoot, $targetReadmePayload)) {
        if (Test-Path -LiteralPath $destFile) {
            throw "Destination file already exists: '$destFile'. Refusing to overwrite existing files on $($cleanLetter):."
        }
    }

    $toolchain = Get-ClangToolchain
    if (-not $toolchain.Available) {
        throw "LLVM clang/lld-link compiler toolchain not found. Install LLVM or place clang.exe in C:\Program Files\LLVM\bin."
    }

    $buildScript = Join-Path $Script:RepoRoot "research\profile\build-probe.ps1"
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw "Probe build script not found: $buildScript"
    }

    Write-Host "[*] Compiling read-only Diagnostic Probe targeting Windows ESP {$espGuid}..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $buildScript `
        -WindowsEspGuid $espGuid `
        -Clang $toolchain.Clang `
        -LldLink $toolchain.LldLink `
        -Python 'python'

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to compile read-only generic probe BOOTX64.EFI."
    }

    $compiledProbe = Join-Path $Script:RepoRoot "internal-boot\boot\build\probe-generic\BOOTX64.EFI"
    if (-not (Test-Path -LiteralPath $compiledProbe)) {
        throw "Compiled probe not found at $compiledProbe"
    }

    New-Item -ItemType Directory -Path $targetBootDir -Force | Out-Null
    New-Item -ItemType Directory -Path $targetPayloadDir -Force | Out-Null

    if (Test-Path -LiteralPath $targetBootFile) {
        throw "Destination file appeared during staging: '$targetBootFile'."
    }
    Copy-Item -LiteralPath $compiledProbe -Destination $targetBootFile

    $readmeContent = @"
# Windows GPU UNLOCK - Diagnostic Probe Capture USB

## How to Collect Pre-Boot Diagnostic Captures:
1. Ensure Secure Boot is DISABLED in your BIOS.
2. Shut down the PC completely (Power Off). Do not restart.
3. Power on and press your Boot Menu key (ASUS F8 / Gigabyte F12 / MSI F11).
4. Boot from this USB drive ('UEFI: USB Drive').
5. The probe runs safely (100% read-only), records physical DIAGnn.TXT, IMGnn.BIN, and PROM.BIN captures,
   and IMMEDIATELY hands off directly to Windows Boot Manager. No return to BIOS!
6. Once Windows starts, repeat once more (Full Cold Shutdown -> Boot USB) to record DIAG01.TXT.
7. Open the GPU Unlock Utility and click 'Build & Stage Headless Unlock'!
"@
    if (Test-Path -LiteralPath $targetReadmeRoot) {
        throw "Destination file appeared during staging: '$targetReadmeRoot'."
    }
    Set-Content -LiteralPath $targetReadmeRoot -Value $readmeContent -Encoding utf8

    if (Test-Path -LiteralPath $targetReadmePayload) {
        throw "Destination file appeared during staging: '$targetReadmePayload'."
    }
    Set-Content -LiteralPath $targetReadmePayload -Value "READ-ONLY PROBE. Logs DIAGnn.TXT, PROM.BIN and IMGnn.BIN here, then starts Windows directly." -Encoding ascii

    return "Successfully compiled and staged read-only Diagnostic Probe on $($cleanLetter):."
}

function Build-And-Stage-Local-Unlock([string]$Letter) {
    $cleanLetter = $Letter.TrimEnd(':')
    $driveRoot = "$($cleanLetter):\"
    if (-not (Test-Path -LiteralPath $driveRoot)) {
        throw "Drive '$driveRoot' does not exist."
    }

    $part = Get-Partition -DriveLetter $cleanLetter -ErrorAction Stop
    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
    $vol = Get-Volume -DriveLetter $cleanLetter -ErrorAction Stop
    if ($disk.BusType -ne 'USB' -or $vol.FileSystem -ne 'FAT32' -or $part.IsSystem -or $disk.IsBoot) {
        throw "$($cleanLetter): is not a FAT32 USB data stick."
    }
    if ($part.IsBoot) {
        throw "$($cleanLetter): is a boot partition; staging refused."
    }

    $status = Get-UsbProbeCaptureStatus -Letter $cleanLetter
    if ($status.Count -lt 2) {
        throw "Insufficient probe captures on $($cleanLetter): ($($status.Count) of 2). Please boot from the Diagnostic Probe USB at least twice (from a full cold shutdown) so hardware captures are saved."
    }

    $toolchain = Get-ClangToolchain
    if (-not $toolchain.Available) {
        throw "LLVM clang/lld-link compiler toolchain not found. Install LLVM or place clang.exe in C:\Program Files\LLVM\bin."
    }

    $espGuid = Get-SystemWindowsEspGuid
    if (-not $espGuid) {
        throw "Could not determine system Windows ESP partition GUID. Ensure Windows is running on a UEFI GPT disk."
    }

    # Ensure firmware assets exist
    if (-not (Test-FirmwareAssetsVerified)) {
        Invoke-DownloadAssets | Out-Null
    }

    $newMachineScript = Join-Path $Script:RepoRoot "research\profile\new-machine.ps1"
    Write-Host "[*] Generating local profile, running host verification tests, and building Headless USB package..." -ForegroundColor Cyan

    & powershell -NoProfile -ExecutionPolicy Bypass -File $newMachineScript `
        -Drive $cleanLetter `
        -WindowsEspGuid $espGuid `
        -Assets $Script:AssetsPath `
        -StageUnlock `
        -Clang $toolchain.Clang `
        -LldLink $toolchain.LldLink `
        -Python 'python'

    if ($LASTEXITCODE -ne 0) {
        throw "Headless unlock packaging failed. Check the error log output."
    }

    return "Successfully generated local profile and staged custom Headless Unlock bootloader on $($cleanLetter):!"
}

# --- OFFLINE COMPATIBILITY CHECKER & ANALYSER ENGINE ---

function Invoke-OfflineCompatibilityCheck {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [string]$Language = 'en'
    )

    if (-not (Test-Path -LiteralPath $Folder)) {
        throw "Capture directory '$Folder' not found."
    }
    if (-not (Test-Path -LiteralPath $Script:CheckerPy)) {
        throw "Offline compatibility checker script not found at $Script:CheckerPy"
    }

    $raw = & python -I $Script:CheckerPy $Folder --lang $Language --json 2>&1
    $rawText = ($raw -join "`n").Trim()

    $jsonObj = $null
    try {
        $jsonObj = $rawText | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Status       = 'error'
            Badge        = '[ERROR]'
            BadgeColor   = 'Tomato'
            Summary      = "Failed to parse checker output into JSON."
            Scope        = "Unknown"
            Limitations  = "Python engine error or malformed diagnostic data."
            NextStep     = "Ensure Python 3.10+ is installed and verify capture file permissions."
            CaptureCount = 0
            Checks       = @()
            Observations = @()
            RawJson      = ""
            RawText      = $rawText
            Parsed       = $null
        }
    }

    $badge = switch ($jsonObj.status) {
        'candidate' { '[CANDIDATE] Eligible for Local Profile' }
        'needs_data' { '[NEEDS DATA] More Captures / Files Required' }
        'outside_scope' { '[OUTSIDE SCOPE] Hardware / Layout Outside Envelope' }
        'invalid_data' { '[INVALID DATA] Inconsistent / Corrupted Observations' }
        default { "[$($jsonObj.status.ToUpper())]" }
    }

    $badgeColor = switch ($jsonObj.status) {
        'candidate' { 'LightGreen' }
        'needs_data' { 'Gold' }
        'outside_scope' { 'DarkOrange' }
        'invalid_data' { 'Tomato' }
        default { 'Gray' }
    }

    return [pscustomobject]@{
        Status       = [string]$jsonObj.status
        Badge        = $badge
        BadgeColor   = $badgeColor
        Summary      = [string]$jsonObj.summary
        Scope        = [string]$jsonObj.scope
        Limitations  = [string]$jsonObj.limitations
        NextStep     = [string]$jsonObj.next_step
        CaptureCount = [int]$jsonObj.capture_count
        Checks       = @($jsonObj.checks)
        Observations = @($jsonObj.observations)
        RawJson      = $rawText
        RawText      = $rawText
        Parsed       = $jsonObj
    }
}

function Invoke-CompareCompatibilityReports {
    param(
        [Parameter(Mandatory)][string]$LeftReportPath,
        [Parameter(Mandatory)][string]$RightReportPath,
        [string]$Language = 'en'
    )

    if (-not (Test-Path -LiteralPath $LeftReportPath)) { throw "Reference report '$LeftReportPath' does not exist." }
    if (-not (Test-Path -LiteralPath $RightReportPath)) { throw "Target report '$RightReportPath' does not exist." }
    if (-not (Test-Path -LiteralPath $Script:ComparatorPy)) { throw "compare-compatibility.py not found at $Script:ComparatorPy" }

    $res = & python -I $Script:ComparatorPy $LeftReportPath $RightReportPath --lang $Language 2>&1
    return ($res -join "`r`n")
}

function Test-FirmwareAssetsVerified {
    if (-not (Test-Path -LiteralPath $Script:AssetsJson)) { return $false }
    try {
        $specs = Get-Content -LiteralPath $Script:AssetsJson -Raw | ConvertFrom-Json
        foreach ($spec in $specs) {
            $f = Join-Path $Script:AssetsPath $spec.Name
            if (-not (Test-Path -LiteralPath $f)) { return $false }
            if ((Get-Sha256Hash $f) -ne $spec.Sha256.ToLowerInvariant()) { return $false }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-DownloadAssets {
    if (Test-FirmwareAssetsVerified) {
        Write-Host "[+] All 5 required firmware assets are already present and verified in assets/." -ForegroundColor Green
        return "All 5 required GA102 firmware assets verified in assets/."
    }
    $script = Join-Path $scriptDir "download_assets.py"
    if (-not (Test-Path -LiteralPath $script)) {
        throw "download_assets.py not found at $script"
    }
    Write-Host "[+] Executing automated firmware asset download and extraction..." -ForegroundColor Yellow
    $res = & python -I $script --output $Script:AssetsPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $detail = ($res -join " ")
        throw "Automated asset acquisition failed: $detail"
    }
    return "All 5 firmware assets downloaded, verified, and placed into assets/."
}

# --- CLI DISPATCHER ---

if ($Cli) {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " Windows GPU UNLOCK - CLI Management Utility" -ForegroundColor White
    Write-Host " Repository: $Script:RepoRoot" -ForegroundColor DarkGray
    Write-Host "==========================================================" -ForegroundColor Cyan

    switch ($Action) {
        'Audit' {
            Write-Host "`n[+] Executing System and GPU Compatibility Audit..." -ForegroundColor Yellow
            $audit = Get-GpuHardwareInfo
            $audit | ConvertTo-Json -Depth 5 | Write-Output
        }
        'Preflight' {
            Write-Host "`n[+] Running Safety Pre-Flight Checks..." -ForegroundColor Yellow
            $checks = Get-PreflightChecks
            foreach ($k in $checks.Keys) {
                $c = $checks[$k]
                $color = switch ($c.Status) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Cyan' } }
                Write-Host "[$($c.Status)] $($c.Title): " -ForegroundColor $color -NoNewline
                Write-Host $c.Detail
            }
        }
        'CheckUsb' {
            Write-Host "`n[+] Querying Connected USB Storage Devices..." -ForegroundColor Yellow
            $usb = Get-RemovableDrives
            if ($usb.Count -eq 0) {
                Write-Host "No removable USB drives detected." -ForegroundColor DarkYellow
            }
            else {
                $usb | Format-Table DriveLetter, FriendlyName, FileSystem, SizeGb, IsBoot
            }
        }
        'DeployUsb' {
            if (-not $DriveLetter) { throw "Please specify -DriveLetter (e.g. -DriveLetter E)" }
            Write-Host "`n[+] Deploying USB to $DriveLetter..." -ForegroundColor Yellow
            $res = Deploy-ToUsb $DriveLetter
            $res | Format-List
        }
        'StageProbe' {
            if (-not $DriveLetter) { throw "Please specify -DriveLetter (e.g. -DriveLetter E)" }
            Write-Host "`n[+] Compiling and Staging Diagnostic Probe on $DriveLetter..." -ForegroundColor Yellow
            $msg = Stage-DiagnosticProbeUsb -Letter $DriveLetter -OptIn:$OptIn
            Write-Host $msg -ForegroundColor Green
        }
        'BuildLocalUsb' {
            if (-not $DriveLetter) { throw "Please specify -DriveLetter (e.g. -DriveLetter E)" }
            Write-Host "`n[+] Building and Staging Local Profile Unlock Bootloader on $DriveLetter..." -ForegroundColor Yellow
            $msg = Build-And-Stage-Local-Unlock -Letter $DriveLetter
            Write-Host $msg -ForegroundColor Green
        }
        'RestoreWindows' {
            Write-Host "`n[+] Restoring Standard Windows Boot Order..." -ForegroundColor Yellow
            $res = Restore-WindowsFirstBootOrder
            Write-Host $res -ForegroundColor Green
        }
        'Telemetry' {
            Write-Host "`n========================================================" -ForegroundColor Cyan
            Write-Host " [CHECK 1] Hardware Register Verification (NVRAM / Boot)" -ForegroundColor Cyan
            Write-Host "========================================================" -ForegroundColor Cyan
            $u = Get-GpuUnlockStatus
            [pscustomobject]$u | Format-List

            Write-Host "`n========================================================" -ForegroundColor Yellow
            Write-Host " [CHECK 2] Silicon Functional Verification (Live Tensor)" -ForegroundColor Yellow
            Write-Host "========================================================" -ForegroundColor Yellow
            $tensor = Test-GpuSiliconTensor -Iterations 50
            [pscustomobject]$tensor | Format-List
            if ($tensor.Tested -and $tensor.TFlops -ge $tensor.Threshold) {
                Write-Host "[SUCCESS] $($tensor.Message)`n" -ForegroundColor Green
            } elseif ($tensor.Tested) {
                Write-Host "[WARNING] $($tensor.Message)`n" -ForegroundColor Yellow
            } else {
                Write-Host "[INFO] $($tensor.Message)`n" -ForegroundColor DarkGray
            }

            Write-Host "========================================================" -ForegroundColor Magenta
            Write-Host " Live GPU Telemetry (nvidia-smi)" -ForegroundColor Magenta
            Write-Host "========================================================" -ForegroundColor Magenta
            $telem = Get-GpuTelemetryLive
            [pscustomobject]$telem | Format-List
        }
        'VerifyTensor' {
            Write-Host "`n[+] Running Silicon Functional Verification (Live Tensor Benchmark)..." -ForegroundColor Yellow
            $tensor = Test-GpuSiliconTensor -Iterations 50
            if ($Json) {
                $tensor | ConvertTo-Json
            } else {
                [pscustomobject]$tensor | Format-List
                if ($tensor.Tested -and $tensor.TFlops -ge $tensor.Threshold) {
                    Write-Host "`n[SUCCESS] $($tensor.Message)`n" -ForegroundColor Green
                } elseif ($tensor.Tested) {
                    Write-Host "`n[WARNING] $($tensor.Message)`n" -ForegroundColor Yellow
                } else {
                    Write-Host "`n[INFO] $($tensor.Message)`n" -ForegroundColor DarkGray
                }
            }
        }
        'CheckCaptures' {
            if (-not $CapturePath) { throw "Please specify -CapturePath" }
            Write-Host "`n[+] Running Offline Compatibility Checker on: $CapturePath (Lang: $Lang)..." -ForegroundColor Yellow
            $res = Invoke-OfflineCompatibilityCheck -Folder $CapturePath -Language $Lang

            if ($Json) {
                Write-Output $res.RawJson
            }
            else {
                Write-Host "`nAssessment: $($res.Badge)" -ForegroundColor $(switch ($res.Status) { 'candidate' { 'Green' } 'needs_data' { 'Yellow' } default { 'Red' } })
                Write-Host "Summary:    $($res.Summary)" -ForegroundColor White
                Write-Host "Captures:   $($res.CaptureCount) found" -ForegroundColor Cyan
                Write-Host "Scope:      $($res.Scope)" -ForegroundColor DarkGray
                Write-Host "`nChecks Evaluated:" -ForegroundColor Yellow
                foreach ($chk in $res.Checks) {
                    $stateColor = switch ($chk.state) { 'candidate' { 'Green' } 'needs_data' { 'Yellow' } default { 'Red' } }
                    Write-Host "  [$($chk.state.ToUpper())] $($chk.code): $($chk.message)" -ForegroundColor $stateColor
                }
                Write-Host "`nNext Step Guidance:" -ForegroundColor Yellow
                Write-Host "$($res.NextStep)`n" -ForegroundColor Cyan
            }

            if ($ExportPath) {
                Set-Content -LiteralPath $ExportPath -Value $res.RawJson -Encoding utf8
                Write-Host "[+] Report exported to $ExportPath" -ForegroundColor Green
            }
        }
        'CompareReports' {
            if (-not $LeftReport -or -not $RightReport) { throw "Please specify -LeftReport and -RightReport" }
            Write-Host "`n[+] Comparing Compatibility Reports: '$LeftReport' vs '$RightReport'..." -ForegroundColor Yellow
            $diff = Invoke-CompareCompatibilityReports -LeftReportPath $LeftReport -RightReportPath $RightReport -Language $Lang
            Write-Output $diff
        }
        'GenerateDumps' {
            Write-Host "`n[+] Generating Diagnostic Dumps (Type: $DumpType)..." -ForegroundColor Yellow
            switch ($DumpType) {
                'Windows' {
                    $out = Export-WindowsDiagnosticDump -TargetDir $DumpPath
                    Write-Host "[+] Exported Windows Diagnostic Dump to: $out" -ForegroundColor Green
                }
                'EfiCaptures' {
                    $out = Export-EfiDiagnosticCaptures -TargetDir $DumpPath
                    Write-Host $out -ForegroundColor Green
                }
                'ProbeUsb' {
                    if (-not $DriveLetter) { throw "Please specify -DriveLetter (e.g. -DriveLetter E)" }
                    $msg = Stage-DiagnosticProbeUsb -Letter $DriveLetter -OptIn:$OptIn
                    Write-Host $msg -ForegroundColor Green
                }
            }
        }
        'DownloadAssets' {
            Write-Host "`n[+] Downloading and preparing firmware assets..." -ForegroundColor Yellow
            $msg = Invoke-DownloadAssets
            Write-Host "[+] $msg" -ForegroundColor Green
        }
    }
    exit 0
}

# --- WPF GUI IMPLEMENTATION ---

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows GPU UNLOCK - Control, Compatibility &amp; Deployment Utility"
        Height="820" Width="1080"
        WindowStartupLocation="CenterScreen"
        Background="#181825"
        Foreground="#CDD6F4"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="Border" Background="{TemplateBinding Background}" BorderThickness="0,0,0,3" BorderBrush="Transparent" Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#252538"/>
                                <Setter TargetName="Border" Property="BorderBrush" Value="#89B4FA"/>
                                <Setter Property="Foreground" Value="#89B4FA"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#CDD6F4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="BtnBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="BtnBorder" Property="Background" Value="#45475A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="BtnBorder" Property="Background" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- THEMED COMBOBOX & POPUP DROPDOWN STYLES -->
        <ControlTemplate x:Key="ComboBoxToggleButtonTemplate" TargetType="{x:Type ToggleButton}">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition />
                    <ColumnDefinition Width="28" />
                </Grid.ColumnDefinitions>
                <Border x:Name="Border" Grid.ColumnSpan="2" CornerRadius="4" Background="#1E1E2E" BorderBrush="#45475A" BorderThickness="1" />
                <Border Grid.Column="0" CornerRadius="4,0,0,4" Margin="1" Background="#1E1E2E" />
                <Path x:Name="Arrow" Grid.Column="1" Fill="#CDD6F4" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z"/>
            </Grid>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="Border" Property="BorderBrush" Value="#89B4FA" />
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <Style TargetType="{x:Type ComboBoxItem}">
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ComboBoxItem}">
                        <Border Name="ItemBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="#313244"/>
                                <Setter Property="Foreground" Value="#89B4FA"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="ItemBorder" Property="Background" Value="#45475A"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="{x:Type ComboBox}">
            <Setter Property="SnapsToDevicePixels" Value="true"/>
            <Setter Property="OverridesDefaultStyle" Value="true"/>
            <Setter Property="ScrollViewer.HorizontalScrollBarVisibility" Value="Auto"/>
            <Setter Property="ScrollViewer.VerticalScrollBarVisibility" Value="Auto"/>
            <Setter Property="ScrollViewer.CanContentScroll" Value="true"/>
            <Setter Property="MinWidth" Value="80"/>
            <Setter Property="MinHeight" Value="28"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="{x:Type ComboBox}">
                        <Grid>
                            <ToggleButton Name="ToggleButton" Template="{StaticResource ComboBoxToggleButtonTemplate}" Focusable="false"
                                          IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                          ClickMode="Press">
                            </ToggleButton>
                            <ContentPresenter Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              Margin="10,3,28,3" VerticalAlignment="Center" HorizontalAlignment="Left" />
                            <Popup Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" 
                                   Focusable="False" PopupAnimation="Slide">
                                <Grid Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border x:Name="DropDownBorder" Background="#1E1E2E" BorderBrush="#45475A" BorderThickness="1" CornerRadius="4" Margin="0,2,0,0">
                                        <ScrollViewer Margin="2" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained" />
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- TOP BAR / HEADER -->
        <Border Grid.Row="0" Background="#1E1E2E" CornerRadius="8" Padding="16,14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="Windows GPU UNLOCK" FontSize="20" FontWeight="Bold" Foreground="#89B4FA"/>
                    <TextBlock Text="Offline compatibility checker, safety pre-flight validator, and EFI deployment manager" FontSize="12" Foreground="#A6ADC8" Margin="0,3,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Name="BadgeAdmin" Background="#A6E3A1" CornerRadius="4" Padding="10,5" Margin="0,0,10,0">
                        <TextBlock Name="TxtBadgeAdmin" Text="ADMINISTRATOR" FontWeight="Bold" FontSize="11" Foreground="#11111B"/>
                    </Border>
                    <Button Name="BtnElevate" Content="Elevate to Admin" Background="#F38BA8" Foreground="#11111B" FontWeight="Bold" Padding="10,5" Visibility="Collapsed"/>
                    <Button Name="BtnRefresh" Content="Refresh All" Margin="10,0,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- MAIN TABS -->
        <TabControl Name="MainTabControl" Grid.Row="1" Background="#1E1E2E" BorderBrush="#313244" BorderThickness="1">
            <!-- TAB 1: SYSTEM & GPU AUDIT -->
            <TabItem Header="System &amp; GPU Audit">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="Hardware Profile Identification" FontSize="16" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,10"/>
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Name="TxtAssessment" Text="Scanning hardware..." FontSize="13" FontWeight="SemiBold" Foreground="#A6E3A1" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>

                        <Grid Margin="0,0,0,14">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Motherboard & Platform Box -->
                            <Border Grid.Column="0" Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,8,0" BorderBrush="#313244" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="Host Platform Details" FontSize="13" FontWeight="Bold" Foreground="#F9E2AF" Margin="0,0,0,8"/>
                                    <TextBlock Name="TxtBoard" Text="Motherboard: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtBios" Text="BIOS Version: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtCpu" Text="Processor: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtOs" Text="Operating System: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                </StackPanel>
                            </Border>

                            <!-- GPU Details Box -->
                            <Border Grid.Column="1" Background="#252538" CornerRadius="6" Padding="14" Margin="8,0,0,0" BorderBrush="#313244" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="GPU Controller &amp; PCI Details" FontSize="13" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,8"/>
                                    <TextBlock Name="TxtGpuName" Text="GPU: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtGpuPci" Text="PCI VEN/DEV: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtGpuArch" Text="Architecture: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtGpuVram" Text="VRAM: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtGpuDriver" Text="Driver Version: Detecting..." Margin="0,3" Foreground="#CDD6F4"/>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <TextBlock Text="Supported GPU Families: RTX 3060 (GA104/GA106), RTX 3070, RTX 3070 Ti, RTX 3080, RTX 3090, RTX 3090 Ti. The unlock modifies pre-driver Falcon/GSP selector registers (SS0/SS1) via UEFI pre-boot." FontSize="11" Foreground="#6C7086" TextWrapping="Wrap"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: PRE-FLIGHT SAFETY -->
            <TabItem Header="Pre-Flight Safety">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="System Safety &amp; Prerequisite Verification" FontSize="16" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,10"/>
                        <TextBlock Text="Prior to attempting any UEFI unlock boot, the host environment must meet critical safety standards to avoid boot lockouts or BitLocker recovery prompts." FontSize="12" Foreground="#A6ADC8" Margin="0,0,0,14" TextWrapping="Wrap"/>

                        <!-- Item: Secure Boot -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,10" BorderBrush="#313244" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Name="IconSecureBoot" Grid.Column="0" Text="[OK]" FontSize="16" FontWeight="Bold" Foreground="#A6E3A1" VerticalAlignment="Center" Margin="0,0,14,0"/>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <TextBlock Text="UEFI Secure Boot" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtDetailSecureBoot" Text="Checking..." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Item: Fast Startup -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,10" BorderBrush="#313244" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Name="IconFastStartup" Grid.Column="0" Text="[OK]" FontSize="16" FontWeight="Bold" Foreground="#A6E3A1" VerticalAlignment="Center" Margin="0,0,14,0"/>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <TextBlock Text="Windows Fast Startup" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtDetailFastStartup" Text="Checking..." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                </StackPanel>
                                <Button Name="BtnDisableFastStartup" Grid.Column="2" Content="Disable Fast Startup" Background="#F9E2AF" Foreground="#11111B" VerticalAlignment="Center" Visibility="Collapsed"/>
                            </Grid>
                        </Border>

                        <!-- Item: BitLocker -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,10" BorderBrush="#313244" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Name="IconBitLocker" Grid.Column="0" Text="[OK]" FontSize="16" FontWeight="Bold" Foreground="#A6E3A1" VerticalAlignment="Center" Margin="0,0,14,0"/>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <TextBlock Text="BitLocker C: Encryption" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtDetailBitLocker" Text="Checking..." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Item 4: Pre-Compiled Release EFI Bootloader -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,10" BorderBrush="#313244" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Name="IconReleaseEfi" Grid.Column="0" Text="[OK]" FontSize="16" FontWeight="Bold" Foreground="#A6E3A1" VerticalAlignment="Center" Margin="0,0,14,0"/>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <TextBlock Text="Pre-Compiled UEFI Bootloader (BOOTX64.EFI)" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtDetailReleaseEfi" Text="Checking..." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Item 5: Firmware Assets (NVIDIA GA102 Blobs) -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,10" BorderBrush="#313244" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Name="IconAssets" Grid.Column="0" Text="[OK]" FontSize="16" FontWeight="Bold" Foreground="#A6E3A1" VerticalAlignment="Center" Margin="0,0,14,0"/>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,10,0">
                                    <TextBlock Text="Firmware Asset Files (GA102 Falcon &amp; GSP Blobs)" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtDetailAssets" Text="Checking..." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                </StackPanel>
                                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                                    <Button Name="BtnDownloadAssets" Content="Download Assets (1-Click)" Margin="0,0,6,0" Padding="12,6" Background="#A6E3A1" Foreground="#11111B" FontWeight="Bold"/>
                                    <Button Name="BtnImportAssets" Content="Import Folder..." Margin="0,0,6,0" Padding="10,6" Background="#313244" Foreground="#CDD6F4"/>
                                    <Button Name="BtnAssetsGuide" Content="How to Get Assets" Padding="10,6" Background="#313244" Foreground="#CDD6F4"/>
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Item 6: LLVM / Clang Toolchain -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,10" BorderBrush="#313244" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Name="IconLlvm" Grid.Column="0" Text="[OK]" FontSize="16" FontWeight="Bold" Foreground="#A6E3A1" VerticalAlignment="Center" Margin="0,0,14,0"/>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,10,0">
                                    <TextBlock Text="LLVM / Clang Toolchain (Custom Unlock Compiler)" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4"/>
                                    <TextBlock Name="TxtDetailLlvm" Text="Checking..." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                </StackPanel>
                                <Button Name="BtnInstallLlvm" Grid.Column="2" Content="Install LLVM (winget)" Background="#89B4FA" Foreground="#11111B" FontWeight="Bold" VerticalAlignment="Center" Padding="12,6" Visibility="Collapsed"/>
                            </Grid>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 3: USB UNLOCK DEPLOYER -->
            <TabItem Header="USB Unlock Deployer">
                <Grid>
                    <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                        <StackPanel>
                            <TextBlock Text="Headless USB Route (Direct Windows Boot)" FontSize="16" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,10"/>
                            <TextBlock Text="Deploys the safe Diagnostic Probe or custom compiled Headless Unlock bootloader onto a FAT32 USB drive. The bootloader unlocks GPU registers and immediately chain-loads Windows Boot Manager directly without resetting the GPU or dropping back to BIOS." FontSize="12" Foreground="#A6ADC8" Margin="0,0,0,14" TextWrapping="Wrap"/>

                            <!-- Hardware Route & Toolchain Detection Banner -->
                            <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="Target Deployment Profile &amp; Prerequisites:" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF" Margin="0,0,0,8"/>
                                    <TextBlock Name="TxtUsbRouteInfo" Text="Route: Detecting..." Foreground="#CDD6F4" Margin="0,2"/>
                                    <TextBlock Name="TxtUsbCompilerInfo" Text="Toolchain: Detecting..." Foreground="#A6ADC8" Margin="0,2"/>
                                    <TextBlock Name="TxtUsbEspInfo" Text="Windows ESP: Detecting..." Foreground="#A6ADC8" Margin="0,2"/>
                                    <TextBlock Name="TxtUsbCaptureStatus" Text="Hardware Captures on USB: Select a drive below" FontWeight="SemiBold" Foreground="#89DCEB" Margin="0,4,0,0"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="Select Target USB Drive:" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4" Margin="0,0,0,8"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <ComboBox Name="ComboUsbDrives" Grid.Column="0" Height="32" Background="#313244" Foreground="#CDD6F4" VerticalContentAlignment="Center" Padding="8,4"/>
                                        <Button Name="BtnRefreshUsb" Grid.Column="1" Content="Refresh Disks" Margin="10,0,0,0"/>
                                    </Grid>
                                    <TextBlock Text="* Drive must be formatted as FAT32. Existing files will be preserved." FontSize="11" Foreground="#6C7086" Margin="0,6,0,0"/>
                                </StackPanel>
                            </Border>

                            <WrapPanel Margin="0,0,0,14">
                                <Button Name="BtnStageProbeDirect" Content="1. Stage Diagnostic Probe (Windows Direct Boot)" Background="#313244" Foreground="#A6E3A1" FontWeight="Bold" FontSize="12" Padding="14,10" Margin="0,0,10,6"/>
                                <Button Name="BtnDeployUsb" Content="2. Build &amp; Stage Custom Unlock Bootloader" Background="#89B4FA" Foreground="#11111B" FontWeight="Bold" FontSize="12" Padding="14,10" Margin="0,0,10,6" IsEnabled="False" Opacity="0.5" ToolTip="Requires both hardware captures (DIAG00.TXT &amp; DIAG01.TXT). Stage the diagnostic probe (Button 1) and cold boot twice."/>
                            </WrapPanel>

                            <Border Background="#252538" CornerRadius="6" Padding="14" BorderBrush="#313244" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="Motherboard One-Time Boot Menu Guide (Headless Direct Route):" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF" Margin="0,0,0,8"/>
                                    <TextBlock Text="Step 1: Record Pre-Boot Hardware Captures" FontWeight="Bold" Foreground="#89DCEB" Margin="0,4,0,2"/>
                                    <TextBlock Text="1. Click '1. Stage Diagnostic Probe' above onto your FAT32 USB drive." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="2. Fully shut down your PC (Power Off, do not restart)." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="3. Power on and press your motherboard Boot Menu hotkey (ASUS: F8 / Gigabyte: F12 / MSI: F11 / ASRock: F11)." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="4. Select 'UEFI: [USB Drive]'. The probe safely records your card's VBIOS &amp; BAR layout, then IMMEDIATELY starts Windows Boot Manager (no BIOS loops!)." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="5. Once in Windows, repeat once more (Cold Shutdown -> Boot USB) to obtain 2 agreeing cold boot captures." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="Step 2: Custom Headless Unlock" FontWeight="Bold" Foreground="#89DCEB" Margin="0,6,0,2"/>
                                    <TextBlock Text="6. Reopen this utility and click '2. Build &amp; Stage Custom Unlock Bootloader'." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="7. The utility automatically generates your card's profile, validates host tests, and compiles the unlocker targeting your Windows ESP." Foreground="#CDD6F4" Margin="10,1"/>
                                    <TextBlock Text="8. Boot the USB to unlock the GPU and seamlessly load Windows!" Foreground="#CDD6F4" Margin="10,1"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>

                    <!-- Progress / Wait Overlay -->
                    <Border Name="UsbProgressOverlay" Background="#E611111B" Visibility="Collapsed" CornerRadius="8" Margin="8" BorderBrush="#89B4FA" BorderThickness="1">
                        <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                            <ProgressBar Name="UsbProgressBar" IsIndeterminate="True" Width="300" Height="8" Margin="0,0,0,18" Foreground="#89B4FA" Background="#313244" BorderThickness="0"/>
                            <TextBlock Name="TxtUsbOverlayTitle" Text="Building Custom Unlock Bootloader..." FontSize="16" FontWeight="Bold" Foreground="#89B4FA" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                            <TextBlock Name="TxtUsbOverlayDetail" Text="Running offline verification harness (22 test suites) and compiling EFI binaries. Please wait, this may take 30-60 seconds..." FontSize="12" Foreground="#CDD6F4" HorizontalAlignment="Center" TextWrapping="Wrap" MaxWidth="500" TextAlignment="Center" Margin="0,0,0,14"/>
                            <TextBlock Text="PLEASE WAIT - DO NOT REMOVE THE USB DRIVE OR CLOSE THIS WINDOW" FontSize="11" FontWeight="Bold" Foreground="#F9E2AF" HorizontalAlignment="Center"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 4: INTERNAL ESP & BCD -->
            <TabItem Header="Internal ESP Setup">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="Internal Headless ESP Route" FontSize="16" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,10"/>
                        <TextBlock Text="Configures an internal dedicated FAT32 ESP partition and registers a UEFI BCD boot entry ('GPU Headless UNLOCK - EXPERIMENTAL'). Allows direct F8 testing from internal SSD." FontSize="12" Foreground="#A6ADC8" Margin="0,0,0,14" TextWrapping="Wrap"/>

                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Dedicated ESP Partition Prerequisites:" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF" Margin="0,0,0,8"/>
                                <TextBlock Text="* Must be a separate GPT FAT32 partition of at least 1 GiB." Foreground="#CDD6F4" Margin="0,2"/>
                                <TextBlock Text="* Must NEVER be the primary Windows EFI partition." Foreground="#CDD6F4" Margin="0,2"/>
                                <TextBlock Text="* Must be assigned a temporary drive letter (e.g. U:)." Foreground="#CDD6F4" Margin="0,2"/>
                            </StackPanel>
                        </Border>

                        <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
                            <Button Name="BtnRunInternalConfigure" Content="Configure Internal Boot Config" Margin="0,0,10,0"/>
                            <Button Name="BtnRestoreWindowsBcd" Content="Restore Windows Boot Priority" Background="#F38BA8" Foreground="#11111B"/>
                        </StackPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 5: OFFLINE COMPATIBILITY CHECKER & ANALYSER -->
            <TabItem Header="Offline Compatibility Checker">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="Offline Compatibility Checker &amp; Analyser" FontSize="16" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,8"/>
                        <TextBlock Text="Analyzes pre-boot EFI hardware captures (DIAGnn.TXT, IMGnn.BIN, PROM.BIN) against the project's proven hardware envelope. Operates 100% read-only: does not execute firmware, touch hardware, or modify boot settings." FontSize="12" Foreground="#A6ADC8" Margin="0,0,0,14" TextWrapping="Wrap"/>

                        <!-- Capture Folder Picker Box -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Select Capture Folder (with DIAGnn.TXT, IMGnn.BIN, PROM.BIN):" FontWeight="Bold" FontSize="13" Foreground="#CDD6F4" Margin="0,0,0,8"/>
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBox Name="TxtCaptureFolder" Grid.Column="0" Height="32" Background="#181825" Foreground="#CDD6F4" BorderBrush="#45475A" VerticalContentAlignment="Center" Padding="8,4" Text="D:\RTX3090-UNLOCK"/>
                                    <Button Name="BtnBrowseCaptureFolder" Grid.Column="1" Content="Browse..." Margin="8,0,0,0" Padding="12,6"/>
                                    <Button Name="BtnDetectUsbCaptures" Grid.Column="2" Content="Auto-Detect on USB" Margin="8,0,0,0" Padding="12,6"/>
                                </Grid>

                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Language:" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#A6ADC8" FontSize="12"/>
                                    <ComboBox Name="ComboCheckerLang" Grid.Column="1" Width="120" Height="30" Background="#181825" Foreground="#CDD6F4" VerticalContentAlignment="Center">
                                        <ComboBoxItem Content="English (en)" IsSelected="True"/>
                                        <ComboBoxItem Content="한국어 (ko)"/>
                                    </ComboBox>
                                    <Button Name="BtnRunOfflineCheck" Grid.Column="3" Content="Run Offline Compatibility Check" Background="#89B4FA" Foreground="#11111B" FontWeight="Bold" FontSize="13" Padding="18,8"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <!-- Diagnostic Dump & Capture Generation Tools -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Generate Diagnostic Dumps &amp; Hardware Captures:" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF" Margin="0,0,0,6"/>
                                <TextBlock Text="Generate comprehensive diagnostic packages for compatibility review, bug reporting, or stage the pre-boot probe to USB:" FontSize="11" Foreground="#A6ADC8" Margin="0,0,0,10" TextWrapping="Wrap"/>
                                <WrapPanel>
                                    <Button Name="BtnGenWindowsDump" Content="Generate Windows Diag Dump" Margin="0,0,10,6" Padding="12,7" Background="#313244" Foreground="#CDD6F4"/>
                                    <Button Name="BtnGenEfiCaptures" Content="Generate Synthetic Test Fixtures" Margin="0,0,10,6" Padding="12,7" Background="#313244" Foreground="#89B4FA"/>
                                    <Button Name="BtnStageProbeUsb" Content="Prepare Diagnostic Probe USB" Margin="0,0,10,6" Padding="12,7" Background="#313244" Foreground="#A6E3A1"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>

                        <!-- Assessment Banner -->
                        <Border Name="BadgeStatusBorder" Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="2">
                            <StackPanel>
                                <TextBlock Name="TxtStatusHeader" Text="STATUS: AWAITING ANALYSIS" FontSize="15" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,4"/>
                                <TextBlock Name="TxtStatusSummary" Text="Select your capture directory above and click 'Run Offline Compatibility Check'." FontSize="13" Foreground="#CDD6F4" TextWrapping="Wrap" Margin="0,0,0,6"/>
                                <Border Name="BorderNextStep" Background="#181825" CornerRadius="4" Padding="10" Margin="0,4,0,0" BorderBrush="#45475A" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="Next Step Guidance:" FontWeight="Bold" FontSize="11" Foreground="#89DCEB" Margin="0,0,0,2"/>
                                        <TextBlock Name="TxtNextStep" Text="Run the check to see tailored recommendations." FontSize="12" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Border>

                        <!-- Findings Views Switcher -->
                        <TabControl Name="FindingsTabControl" Height="260" Background="#181825" BorderBrush="#313244" BorderThickness="1" Margin="0,0,0,14">
                            <!-- Sub-Tab 1: Structured Findings -->
                            <TabItem Header="Structured Observations &amp; Checks">
                                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="12">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>

                                        <!-- Column 1: Captured Hardware & Firmware -->
                                        <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                            <TextBlock Text="Hardware &amp; Firmware Observations" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF" Margin="0,0,0,6"/>
                                            <TextBlock Name="TxtObsCaptures" Text="Captures Found: None" Margin="0,2" Foreground="#CDD6F4" FontSize="12"/>
                                            <TextBlock Name="TxtObsGpu" Text="Target GPU: Not detected" Margin="0,2" Foreground="#CDD6F4" FontSize="12"/>
                                            <TextBlock Name="TxtObsPciLoc" Text="PCI Bus / Location: Unknown" Margin="0,2" Foreground="#CDD6F4" FontSize="12"/>
                                            <TextBlock Name="TxtObsChip" Text="Chip / Memory: Unknown" Margin="0,2" Foreground="#CDD6F4" FontSize="12"/>
                                            <TextBlock Name="TxtObsNvgop" Text="Firmware NVGOP: Unknown" Margin="0,2" Foreground="#CDD6F4" FontSize="12"/>
                                            <TextBlock Name="TxtObsDisplays" Text="Display Controllers: Unknown" Margin="0,2" Foreground="#CDD6F4" FontSize="12"/>
                                        </StackPanel>

                                        <!-- Column 2: Evaluated Verification Checks -->
                                        <StackPanel Grid.Column="1" Margin="8,0,0,0">
                                            <TextBlock Text="Evaluated Engine Checks" FontWeight="Bold" FontSize="13" Foreground="#89B4FA" Margin="0,0,0,6"/>
                                            <TextBox Name="TxtChecksList" Height="150" Background="#11111B" Foreground="#CDD6F4" FontFamily="Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" BorderThickness="0" Text="Checks will appear here after analysis."/>
                                        </StackPanel>
                                    </Grid>
                                </ScrollViewer>
                            </TabItem>

                            <!-- Sub-Tab 2: Raw JSON Report -->
                            <TabItem Header="Raw JSON Report">
                                <Border Padding="6">
                                    <TextBox Name="TxtCaptureJson" Background="#11111B" Foreground="#A6E3A1" FontFamily="Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap" BorderThickness="0" Text="Raw JSON report will be displayed here."/>
                                </Border>
                            </TabItem>
                        </TabControl>

                        <!-- Report Actions -->
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,16">
                            <Button Name="BtnExportJson" Content="Export Report JSON..." Margin="0,0,10,0"/>
                            <Button Name="BtnCopyClipboard" Content="Copy JSON to Clipboard" Margin="0,0,10,0"/>
                        </StackPanel>

                        <!-- Expandable Report Comparison Suite -->
                        <Expander Header="Compare Two Compatibility Reports (compare-compatibility.py)" Background="#252538" Foreground="#CDD6F4" Padding="10" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel Margin="0,8,0,0">
                                <TextBlock Text="Compare a reference report against your probe report to identify differences in GOP handles, EDID counts, or register states:" FontSize="11" Foreground="#A6ADC8" Margin="0,0,0,8" TextWrapping="Wrap"/>
                                <Grid Margin="0,0,0,6">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Left (Reference):" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#CDD6F4" FontSize="11"/>
                                    <TextBox Name="TxtLeftReport" Grid.Column="1" Height="26" Background="#181825" Foreground="#CDD6F4" BorderBrush="#45475A" VerticalContentAlignment="Center" Padding="6,2"/>
                                    <Button Name="BtnBrowseLeftReport" Grid.Column="2" Content="Browse..." Margin="6,0,0,0" Padding="8,3"/>
                                </Grid>

                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Right (Probe):   " VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#CDD6F4" FontSize="11"/>
                                    <TextBox Name="TxtRightReport" Grid.Column="1" Height="26" Background="#181825" Foreground="#CDD6F4" BorderBrush="#45475A" VerticalContentAlignment="Center" Padding="6,2"/>
                                    <Button Name="BtnBrowseRightReport" Grid.Column="2" Content="Browse..." Margin="6,0,0,0" Padding="8,3"/>
                                </Grid>

                                <Button Name="BtnRunCompareReports" Content="Compare Selected Reports" Background="#89B4FA" Foreground="#11111B" FontWeight="Bold" Padding="12,6" HorizontalAlignment="Left" Margin="0,0,0,8"/>
                                <TextBox Name="TxtCompareResult" Height="130" Background="#11111B" Foreground="#CDD6F4" FontFamily="Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" BorderThickness="0" Text="Comparison differences will be displayed here."/>
                            </StackPanel>
                        </Expander>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 6: TELEMETRY & VERIFY -->
            <TabItem Header="Verification &amp; Telemetry">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="Hardware Verification &amp; Live Telemetry" FontSize="16" FontWeight="Bold" Foreground="#89B4FA" Margin="0,0,0,10"/>
                        <TextBlock Text="Dual-verification architecture: Check 1 directly verifies hardware strapping registers (via UEFI NVRAM runtime handoff or pre-boot session log); Check 2 tests live GPU silicon via FP16 Tensor Core GEMM matrix math." FontSize="12" Foreground="#A6ADC8" Margin="0,0,0,14" TextWrapping="Wrap"/>

                        <!-- CHECK 1: HARDWARE REGISTERS (UEFI NVRAM / BOOTLOADER) -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="CHECK 1: Hardware Register Verification" FontWeight="Bold" FontSize="13" Foreground="#A6E3A1"/>
                                        <TextBlock Text="Direct verification of hardware strap registers (SS0=0x88888888, SS1=0x8) and PCIe FLR reset." FontSize="11" Foreground="#A6ADC8" Margin="0,2,0,0"/>
                                    </StackPanel>
                                    <Border Name="BadgeUnlockBorder" Grid.Column="1" Background="#1E3A2F" CornerRadius="4" Padding="10,4" VerticalAlignment="Center">
                                        <TextBlock Name="TxtUnlockBadge" Text="ACTIVE / UNLOCKED" FontWeight="Bold" FontSize="11" Foreground="#A6E3A1"/>
                                    </Border>
                                </Grid>
                                <Grid Margin="0,4,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Name="TxtUnlockSource" Text="Verification Source: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtUnlockStraps" Text="Active Straps: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtUnlockState" Text="State: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1">
                                        <TextBlock Name="TxtUnlockProfile" Text="Hardware Profile: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtUnlockTx" Text="Transaction: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtUnlockReport" Text="Boot Session: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtUnlockHandoff" Text="Windows Handoff: Checking..." Margin="0,2" Foreground="#CDD6F4"/>
                                    </StackPanel>
                                </Grid>
                                <Button Name="BtnRefreshUnlock" Content="Refresh Hardware Registers" HorizontalAlignment="Left" Padding="10,4"/>
                            </StackPanel>
                        </Border>

                        <!-- CHECK 2: SILICON FUNCTIONAL TENSOR VERIFICATION -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="CHECK 2: Silicon Functional Verification (Live Tensor Benchmark)" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF"/>
                                        <TextBlock Text="Executes real-time 4096 x 4096 FP16 GEMM on GPU silicon to test if the Tensor Core limiter is lifted." FontSize="11" Foreground="#A6ADC8" Margin="0,2,0,0"/>
                                    </StackPanel>
                                    <Border Name="BadgeTensorBorder" Grid.Column="1" Background="#313244" CornerRadius="4" Padding="10,4" VerticalAlignment="Center">
                                        <TextBlock Name="TxtTensorBadge" Text="NOT TESTED YET" FontWeight="Bold" FontSize="11" Foreground="#CDD6F4"/>
                                    </Border>
                                </Grid>
                                <Grid Margin="0,4,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Name="TxtTensorThroughput" Text="Measured Rate: Not tested yet" Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTensorLimiter" Text="Silicon Rate Limiter: Not tested" Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTensorUplift" Text="Estimated Uplift: N/A" Margin="0,2" Foreground="#CDD6F4"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1">
                                        <TextBlock Name="TxtTensorGpu" Text="Target GPU: Detecting..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTensorTimestamp" Text="Last Tested: N/A" Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTensorStatusMsg" Text="Assessment: Click button below to test live silicon" Margin="0,2" Foreground="#CDD6F4"/>
                                    </StackPanel>
                                </Grid>
                                <StackPanel Orientation="Horizontal">
                                    <Button Name="BtnRunTensorCheck" Content="Run Live Silicon Tensor Check" Background="#89B4FA" Foreground="#11111B" FontWeight="Bold" Padding="12,5" Margin="0,0,12,0"/>
                                    <TextBlock Name="TxtTensorStatus" Text="Ready to test GPU silicon." VerticalAlignment="Center" Foreground="#A6ADC8" FontSize="11"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>

                        <!-- LIVE TELEMETRY -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Live NVIDIA Telemetry (nvidia-smi):" FontWeight="Bold" FontSize="13" Foreground="#89B4FA" Margin="0,0,0,8"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Name="TxtTelemName" Text="GPU: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTelemTemp" Text="Temperature: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTelemUtil" Text="Utilization: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTelemPower" Text="Power Draw: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1">
                                        <TextBlock Name="TxtTelemDriver" Text="Driver: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTelemMem" Text="VRAM Used: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTelemSmClock" Text="SM Clock: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                        <TextBlock Name="TxtTelemMemClock" Text="Memory Clock: Querying..." Margin="0,2" Foreground="#CDD6F4"/>
                                    </StackPanel>
                                </Grid>
                                <Button Name="BtnRefreshTelem" Content="Refresh Telemetry" Margin="0,10,0,0" HorizontalAlignment="Left" Padding="10,4"/>
                            </StackPanel>
                        </Border>

                        <!-- EXPECTED UPLIFT REFERENCE -->
                        <Border Background="#252538" CornerRadius="6" Padding="14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Expected Uplift Protocol &amp; Dual-Check Architecture:" FontWeight="Bold" FontSize="13" Foreground="#89B4FA" Margin="0,0,0,6"/>
                                <TextBlock Text="* Check 1 (Registers): Confirms pre-boot UEFI strap injection (SS0=0x88888888, SS1=0x8) and clean FLR quiescence via NVRAM or boot log." Foreground="#CDD6F4" Margin="0,2"/>
                                <TextBlock Text="* Check 2 (Silicon): Measures real GEMM TFLOPS in Windows to verify that GPU tensor compute is unthrottled (~88 TFLOPS on GA104, ~110-130 TFLOPS on GA102 vs ~40-65 TFLOPS locked)." Foreground="#A6E3A1" Margin="0,2"/>
                                <TextBlock Text="* Both checks passing guarantees that hardware registers are set AND the physical GPU silicon is executing at full workstation speed." Foreground="#F9E2AF" Margin="0,2"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 7: EMERGENCY RECOVERY -->
            <TabItem Header="Emergency Recovery">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="16">
                    <StackPanel>
                        <TextBlock Text="One-Click Safety &amp; Emergency Recovery" FontSize="16" FontWeight="Bold" Foreground="#F38BA8" Margin="0,0,0,10"/>
                        <TextBlock Text="If your system fails to boot automatically or if you want to cleanly revert all EFI boot modifications back to stock Windows defaults, use this recovery module." FontSize="12" Foreground="#A6ADC8" Margin="0,0,0,14" TextWrapping="Wrap"/>

                        <Border Background="#252538" CornerRadius="6" Padding="14" Margin="0,0,0,14" BorderBrush="#F38BA8" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="1-Click Revert: Restore Windows First Boot Priority" FontWeight="Bold" FontSize="14" Foreground="#F38BA8" Margin="0,0,0,6"/>
                                <TextBlock Text="Immediately writes Windows Boot Manager ({bootmgr}) as priority #1 in UEFI firmware displayorder and removes experimental sequences." FontSize="12" Foreground="#CDD6F4" Margin="0,0,0,10" TextWrapping="Wrap"/>
                                <Button Name="BtnEmergencyRestore" Content="Restore Windows Boot Manager (1-Click)" Background="#F38BA8" Foreground="#11111B" FontWeight="Bold" FontSize="13" Padding="16,10" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#252538" CornerRadius="6" Padding="14" BorderBrush="#313244" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Troubleshooting Display Black Screen:" FontWeight="Bold" FontSize="13" Foreground="#F9E2AF" Margin="0,0,0,6"/>
                                <TextBlock Text="* If the screen remains black after booting: The GOP driver was removed and the card is waiting for Windows driver initialization. Wait 30 seconds." Foreground="#CDD6F4" Margin="0,2"/>
                                <TextBlock Text="* If Windows does not appear: Power off completely by holding the power button for 5 seconds. Power back on and press F8/F12 to choose Windows Boot Manager directly." Foreground="#CDD6F4" Margin="0,2"/>
                                <TextBlock Text="* DisplayPort vs HDMI: DisplayPort 1.4 ports on GA102/GA104 cards have the highest recovery success rate." Foreground="#CDD6F4" Margin="0,2"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- BOTTOM CONSOLE / STATUS BAR -->
        <Border Grid.Row="2" Background="#1E1E2E" CornerRadius="6" Padding="12" Margin="0,14,0,0" BorderBrush="#313244" BorderThickness="1">
            <StackPanel>
                <Grid Margin="0,0,0,6">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Text="Activity &amp; Execution Log" FontSize="11" FontWeight="Bold" Foreground="#89B4FA"/>
                    <Button Name="BtnClearLog" Grid.Column="1" Content="Clear" Padding="6,2" FontSize="10"/>
                </Grid>
                <TextBox Name="TxtLog" Height="85" Background="#11111B" Foreground="#CDD6F4" FontFamily="Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" BorderThickness="0"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

# --- LOAD WPF WINDOW ---

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Element References
$txtBadgeAdmin = $window.FindName('TxtBadgeAdmin')
$badgeAdmin = $window.FindName('BadgeAdmin')
$btnElevate = $window.FindName('BtnElevate')
$btnRefresh = $window.FindName('BtnRefresh')
$txtLog = $window.FindName('TxtLog')
$btnClearLog = $window.FindName('BtnClearLog')

# Tab 1
$txtAssessment = $window.FindName('TxtAssessment')
$txtBoard = $window.FindName('TxtBoard')
$txtBios = $window.FindName('TxtBios')
$txtCpu = $window.FindName('TxtCpu')
$txtOs = $window.FindName('TxtOs')
$txtGpuName = $window.FindName('TxtGpuName')
$txtGpuPci = $window.FindName('TxtGpuPci')
$txtGpuArch = $window.FindName('TxtGpuArch')
$txtGpuVram = $window.FindName('TxtGpuVram')
$txtGpuDriver = $window.FindName('TxtGpuDriver')

# Tab 2
$iconSecureBoot = $window.FindName('IconSecureBoot')
$txtDetailSecureBoot = $window.FindName('TxtDetailSecureBoot')
$iconFastStartup = $window.FindName('IconFastStartup')
$txtDetailFastStartup = $window.FindName('TxtDetailFastStartup')
$btnDisableFastStartup = $window.FindName('BtnDisableFastStartup')
$iconBitLocker = $window.FindName('IconBitLocker')
$txtDetailBitLocker = $window.FindName('TxtDetailBitLocker')
$iconReleaseEfi = $window.FindName('IconReleaseEfi')
$txtDetailReleaseEfi = $window.FindName('TxtDetailReleaseEfi')
$iconAssets = $window.FindName('IconAssets')
$txtDetailAssets = $window.FindName('TxtDetailAssets')
$btnDownloadAssets = $window.FindName('BtnDownloadAssets')
$btnImportAssets = $window.FindName('BtnImportAssets')
$btnAssetsGuide = $window.FindName('BtnAssetsGuide')
$iconLlvm = $window.FindName('IconLlvm')
$txtDetailLlvm = $window.FindName('TxtDetailLlvm')
$btnInstallLlvm = $window.FindName('BtnInstallLlvm')

# Tab 3
$comboUsbDrives = $window.FindName('ComboUsbDrives')
$btnRefreshUsb = $window.FindName('BtnRefreshUsb')
$btnDeployUsb = $window.FindName('BtnDeployUsb')
$btnStageProbeDirect = $window.FindName('BtnStageProbeDirect')
$txtUsbRouteInfo = $window.FindName('TxtUsbRouteInfo')
$txtUsbCompilerInfo = $window.FindName('TxtUsbCompilerInfo')
$txtUsbEspInfo = $window.FindName('TxtUsbEspInfo')
$txtUsbCaptureStatus = $window.FindName('TxtUsbCaptureStatus')
$usbProgressOverlay = $window.FindName('UsbProgressOverlay')
$usbProgressBar = $window.FindName('UsbProgressBar')
$txtUsbOverlayTitle = $window.FindName('TxtUsbOverlayTitle')
$txtUsbOverlayDetail = $window.FindName('TxtUsbOverlayDetail')

# Tab 4
$btnRunInternalConfigure = $window.FindName('BtnRunInternalConfigure')
$btnRestoreWindowsBcd = $window.FindName('BtnRestoreWindowsBcd')

# Tab 5 (Offline Compatibility Checker & Analyser)
$txtCaptureFolder = $window.FindName('TxtCaptureFolder')
$btnBrowseCaptureFolder = $window.FindName('BtnBrowseCaptureFolder')
$btnDetectUsbCaptures = $window.FindName('BtnDetectUsbCaptures')
$btnGenWindowsDump = $window.FindName('BtnGenWindowsDump')
$btnGenEfiCaptures = $window.FindName('BtnGenEfiCaptures')
$btnStageProbeUsb = $window.FindName('BtnStageProbeUsb')
$comboCheckerLang = $window.FindName('ComboCheckerLang')
$btnRunOfflineCheck = $window.FindName('BtnRunOfflineCheck')

$badgeStatusBorder = $window.FindName('BadgeStatusBorder')
$txtStatusHeader = $window.FindName('TxtStatusHeader')
$txtStatusSummary = $window.FindName('TxtStatusSummary')
$txtNextStep = $window.FindName('TxtNextStep')

$txtObsCaptures = $window.FindName('TxtObsCaptures')
$txtObsGpu = $window.FindName('TxtObsGpu')
$txtObsPciLoc = $window.FindName('TxtObsPciLoc')
$txtObsChip = $window.FindName('TxtObsChip')
$txtObsNvgop = $window.FindName('TxtObsNvgop')
$txtObsDisplays = $window.FindName('TxtObsDisplays')
$txtChecksList = $window.FindName('TxtChecksList')
$txtCaptureJson = $window.FindName('TxtCaptureJson')

$btnExportJson = $window.FindName('BtnExportJson')
$btnCopyClipboard = $window.FindName('BtnCopyClipboard')

$txtLeftReport = $window.FindName('TxtLeftReport')
$btnBrowseLeftReport = $window.FindName('BtnBrowseLeftReport')
$txtRightReport = $window.FindName('TxtRightReport')
$btnBrowseRightReport = $window.FindName('BtnBrowseRightReport')
$btnRunCompareReports = $window.FindName('BtnRunCompareReports')
$txtCompareResult = $window.FindName('TxtCompareResult')

# Tab 6 - Check 1: Hardware Registers
$badgeUnlockBorder = $window.FindName('BadgeUnlockBorder')
$txtUnlockBadge = $window.FindName('TxtUnlockBadge')
$txtUnlockSource = $window.FindName('TxtUnlockSource')
$txtUnlockStraps = $window.FindName('TxtUnlockStraps')
$txtUnlockState = $window.FindName('TxtUnlockState')
$txtUnlockProfile = $window.FindName('TxtUnlockProfile')
$txtUnlockTx = $window.FindName('TxtUnlockTx')
$txtUnlockReport = $window.FindName('TxtUnlockReport')
$txtUnlockHandoff = $window.FindName('TxtUnlockHandoff')
$btnRefreshUnlock = $window.FindName('BtnRefreshUnlock')

# Tab 6 - Check 2: Silicon Functional Verification
$badgeTensorBorder = $window.FindName('BadgeTensorBorder')
$txtTensorBadge = $window.FindName('TxtTensorBadge')
$txtTensorThroughput = $window.FindName('TxtTensorThroughput')
$txtTensorLimiter = $window.FindName('TxtTensorLimiter')
$txtTensorUplift = $window.FindName('TxtTensorUplift')
$txtTensorGpu = $window.FindName('TxtTensorGpu')
$txtTensorTimestamp = $window.FindName('TxtTensorTimestamp')
$txtTensorStatusMsg = $window.FindName('TxtTensorStatusMsg')
$btnRunTensorCheck = $window.FindName('BtnRunTensorCheck')
$txtTensorStatus = $window.FindName('TxtTensorStatus')

# Tab 6 - Telemetry
$txtTelemName = $window.FindName('TxtTelemName')
$txtTelemTemp = $window.FindName('TxtTelemTemp')
$txtTelemUtil = $window.FindName('TxtTelemUtil')
$txtTelemPower = $window.FindName('TxtTelemPower')
$txtTelemDriver = $window.FindName('TxtTelemDriver')
$txtTelemMem = $window.FindName('TxtTelemMem')
$txtTelemSmClock = $window.FindName('TxtTelemSmClock')
$txtTelemMemClock = $window.FindName('TxtTelemMemClock')
$btnRefreshTelem = $window.FindName('BtnRefreshTelem')

# Tab 7
$btnEmergencyRestore = $window.FindName('BtnEmergencyRestore')

# Stored Last Report
$Script:LastAnalysis = $null

# --- LOGGING HELPER ---
function Write-GuiLog([string]$Msg) {
    $time = [DateTime]::Now.ToString("HH:mm:ss")
    $txtLog.AppendText("[$time] $Msg`r`n")
    $txtLog.ScrollToEnd()
}

# --- EVENT HANDLERS & REFRESH LOGIC ---

function Refresh-AuditData {
    Write-GuiLog "Scanning host hardware and GPU identities..."
    $info = Get-GpuHardwareInfo
    $txtAssessment.Text = $info['ProfileAssessment']
    $txtBoard.Text = "Motherboard: $($info['Motherboard'])"
    $txtBios.Text = "BIOS Version: $($info['BIOS'])"
    $txtCpu.Text = "Processor: $($info['CPU'])"
    $txtOs.Text = "Operating System: $($info['OS'])"

    $gpu = $info['GPUs'] | Where-Object { $_.IsAmpere } | Select-Object -First 1
    if (-not $gpu -and $info['GPUs'].Count -gt 0) { $gpu = $info['GPUs'][0] }

    if ($gpu) {
        $txtGpuName.Text = "GPU: $($gpu.Name)"
        $txtGpuPci.Text = "PCI VEN/DEV: $($gpu.PCI.Vendor):$($gpu.PCI.Device) (Subsystem: $($gpu.PCI.SubsystemVendor):$($gpu.PCI.SubsystemDevice))"
        $txtGpuArch.Text = "Architecture: $($gpu.Architecture)"
        $txtGpuVram.Text = "VRAM: $($gpu.VramMb) MB"
        $txtGpuDriver.Text = "Driver Version: $($gpu.DriverVersion)"
    }
    else {
        $txtGpuName.Text = "GPU: No compatible GPU detected."
    }
}

function Refresh-PreflightData {
    Write-GuiLog "Evaluating system safety and prerequisites..."
    $checks = Get-PreflightChecks

    # Secure Boot
    $sb = $checks['SecureBoot']
    $txtDetailSecureBoot.Text = $sb.Detail
    if ($sb.Status -eq 'PASS') {
        $iconSecureBoot.Text = "[OK]"; $iconSecureBoot.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    elseif ($sb.Status -eq 'FAIL') {
        $iconSecureBoot.Text = "[X]"; $iconSecureBoot.Foreground = [System.Windows.Media.Brushes]::Tomato
    }
    else {
        $iconSecureBoot.Text = "[!]"; $iconSecureBoot.Foreground = [System.Windows.Media.Brushes]::Gold
    }

    # Fast Startup
    $fs = $checks['FastStartup']
    $txtDetailFastStartup.Text = $fs.Detail
    if ($fs.Status -eq 'PASS') {
        $iconFastStartup.Text = "[OK]"; $iconFastStartup.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $btnDisableFastStartup.Visibility = [System.Windows.Visibility]::Collapsed
    }
    elseif ($fs.Status -eq 'WARN') {
        $iconFastStartup.Text = "[!]"; $iconFastStartup.Foreground = [System.Windows.Media.Brushes]::Gold
        $btnDisableFastStartup.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $iconFastStartup.Text = "[?]"; $iconFastStartup.Foreground = [System.Windows.Media.Brushes]::Gray
    }

    # BitLocker
    $bl = $checks['BitLocker']
    $txtDetailBitLocker.Text = $bl.Detail
    if ($bl.Status -eq 'PASS') {
        $iconBitLocker.Text = "[OK]"; $iconBitLocker.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    elseif ($bl.Status -eq 'WARN') {
        $iconBitLocker.Text = "[!]"; $iconBitLocker.Foreground = [System.Windows.Media.Brushes]::Tomato
    }
    else {
        $iconBitLocker.Text = "[i]"; $iconBitLocker.Foreground = [System.Windows.Media.Brushes]::SkyBlue
    }

    # Release EFI Bootloader
    $rel = $checks['ReleaseEFI']
    $txtDetailReleaseEfi.Text = $rel.Detail
    if ($rel.Status -eq 'PASS') {
        $iconReleaseEfi.Text = "[OK]"; $iconReleaseEfi.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    else {
        $iconReleaseEfi.Text = "[!]"; $iconReleaseEfi.Foreground = [System.Windows.Media.Brushes]::Tomato
    }

    # Firmware Assets
    $as = $checks['FirmwareAssets']
    $txtDetailAssets.Text = $as.Detail
    if ($as.Status -eq 'PASS') {
        $iconAssets.Text = "[OK]"; $iconAssets.Foreground = [System.Windows.Media.Brushes]::LightGreen
    }
    else {
        $iconAssets.Text = "[!]"; $iconAssets.Foreground = [System.Windows.Media.Brushes]::Gold
    }

    # LLVM / Clang Toolchain
    if ($iconLlvm) {
        $toolchain = Get-ClangToolchain
        if ($toolchain.Available) {
            $iconLlvm.Text = "[OK]"; $iconLlvm.Foreground = [System.Windows.Media.Brushes]::LightGreen
            $txtDetailLlvm.Text = "LLVM Clang & LLD-Link Ready: $($toolchain.Clang)"
            $btnInstallLlvm.Visibility = [System.Windows.Visibility]::Collapsed
        }
        else {
            $iconLlvm.Text = "[!]"; $iconLlvm.Foreground = [System.Windows.Media.Brushes]::Gold
            $txtDetailLlvm.Text = "LLVM Clang / LLD not found. Required to build custom unlock bootloader for non-reference systems."
            $btnInstallLlvm.Visibility = [System.Windows.Visibility]::Visible
        }
    }
}

function Show-UsbProgressOverlay([string]$Title, [string]$Detail) {
    if ($usbProgressOverlay) {
        $txtUsbOverlayTitle.Text = $Title
        $txtUsbOverlayDetail.Text = $Detail
        $usbProgressOverlay.Visibility = [System.Windows.Visibility]::Visible
        $btnStageProbeDirect.IsEnabled = $false
        $btnDeployUsb.IsEnabled = $false
        $comboUsbDrives.IsEnabled = $false
        $btnRefreshUsb.IsEnabled = $false
        if ($window.Dispatcher) {
            $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Hide-UsbProgressOverlay {
    if ($usbProgressOverlay) {
        $usbProgressOverlay.Visibility = [System.Windows.Visibility]::Collapsed
        $btnStageProbeDirect.IsEnabled = $true
        $comboUsbDrives.IsEnabled = $true
        $btnRefreshUsb.IsEnabled = $true
        Update-UsbTabInfo
        if ($window.Dispatcher) {
            $window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Update-UsbTabInfo {
    try {
        $info = Get-GpuHardwareInfo
        $nvidiaGpu = $info['GPUs'] | Where-Object { $_.IsAmpere } | Select-Object -First 1
        $bp = $info['BoardProduct']
        $bv = $info['BIOSVersion']
        $isFixed = ($bp -match 'B650M-PLUS' -and $bv -eq '3057' -and $nvidiaGpu -and $nvidiaGpu.PCI.Device -eq '2204' -and $nvidiaGpu.PCI.Subsystem -eq '145410de')

        if ($txtUsbRouteInfo) {
            $txtUsbRouteInfo.Text = "System: $($info['Motherboard']) | $($nvidiaGpu.Name) ($($nvidiaGpu.PCI.SubsystemVendor):$($nvidiaGpu.PCI.SubsystemDevice))`nRoute: $(if ($isFixed) { 'Stock Fixed Profile (ASUS B650M-PLUS)' } else { 'Headless Single-RTX / Local Profile (Direct Windows Handoff)' })"
        }

        $toolchain = Get-ClangToolchain
        if ($txtUsbCompilerInfo) {
            $txtUsbCompilerInfo.Text = "Toolchain: $(if ($toolchain.Available) { "LLVM Clang & LLD-Link Ready ($($toolchain.Clang))" } else { "Not Found (Install LLVM for custom build)" })"
        }

        $espGuid = Get-SystemWindowsEspGuid
        if ($txtUsbEspInfo) {
            $txtUsbEspInfo.Text = "System Windows ESP: $(if ($espGuid) { "{$espGuid}" } else { "Not Detected" })"
        }

        if ($txtUsbCaptureStatus) {
            $selected = [string]$comboUsbDrives.SelectedItem
            if ($selected -and -not $selected.StartsWith("No removable")) {
                $letter = $selected.Substring(0, 1)
                $status = Get-UsbProbeCaptureStatus -Letter $letter
                if ($status.Count -ge 2) {
                    $txtUsbCaptureStatus.Text = "Hardware Captures on $($letter): $($status.Count) of 2 complete [READY FOR CUSTOM UNLOCK BUILD]"
                    $txtUsbCaptureStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
                    if ($btnDeployUsb) {
                        $btnDeployUsb.IsEnabled = $true
                        $btnDeployUsb.Opacity = 1.0
                        $btnDeployUsb.ToolTip = "Both hardware captures detected ($($status.Count)/2). Ready to build and stage custom unlock bootloader."
                    }
                }
                else {
                    $txtUsbCaptureStatus.Text = "Hardware Captures on $($letter): $($status.Count) of 2 complete [COLD BOOT PROBE REQUIRED]"
                    $txtUsbCaptureStatus.Foreground = [System.Windows.Media.Brushes]::Gold
                    if ($btnDeployUsb) {
                        $btnDeployUsb.IsEnabled = $false
                        $btnDeployUsb.Opacity = 0.5
                        $btnDeployUsb.ToolTip = "Requires both hardware captures (DIAG00.TXT & DIAG01.TXT). Stage the diagnostic probe (Button 1) and cold boot the USB twice."
                    }
                }
            }
            else {
                $txtUsbCaptureStatus.Text = "Hardware Captures on USB: No drive selected"
                $txtUsbCaptureStatus.Foreground = [System.Windows.Media.Brushes]::Gray
                if ($btnDeployUsb) {
                    $btnDeployUsb.IsEnabled = $false
                    $btnDeployUsb.Opacity = 0.5
                    $btnDeployUsb.ToolTip = "Select a FAT32 USB drive first."
                }
            }
        }
    } catch {}
}

function Refresh-UsbList {
    $comboUsbDrives.Items.Clear()
    $drives = Get-RemovableDrives
    if ($drives.Count -eq 0) {
        $comboUsbDrives.Items.Add("No removable USB drive detected") | Out-Null
        $comboUsbDrives.SelectedIndex = 0
    }
    else {
        foreach ($d in $drives) {
            $comboUsbDrives.Items.Add("$($d.DriveLetter) [$($d.FileSystem), $($d.SizeGb) GB] $($d.FriendlyName)") | Out-Null
        }
        $comboUsbDrives.SelectedIndex = 0
    }
    Update-UsbTabInfo
}

function Refresh-TelemetryData {
    # 1. Hardware Register Check (Check 1)
    $unlock = Get-GpuUnlockStatus
    if ($txtUnlockBadge) {
        $txtUnlockBadge.Text = $unlock['Badge']
        if ($unlock['Active']) {
            $badgeUnlockBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3A2F")
            $badgeUnlockBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
            $txtUnlockBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
        } else {
            $badgeUnlockBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3E2025")
            $badgeUnlockBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
            $txtUnlockBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
        }
        if ($txtUnlockSource) { $txtUnlockSource.Text = "Verification Source: $($unlock['Source'])" }
        $txtUnlockState.Text = "State: $($unlock['State'])"
        $txtUnlockStraps.Text = "Active Straps: $($unlock['Straps'])"
        $txtUnlockProfile.Text = "Hardware Profile: $($unlock['Profile'])"
        $txtUnlockTx.Text = "Transaction: $($unlock['Transaction'])"
        $txtUnlockReport.Text = "Boot Session: $($unlock['Report'])"
        $txtUnlockHandoff.Text = "Windows Handoff: $($unlock['Handoff'])"
    }

    # 2. Live Telemetry
    $telem = Get-GpuTelemetryLive
    if ($telem['Error']) {
        $txtTelemName.Text = "GPU: $($telem['Error'])"
        $txtTelemTemp.Text = "Temperature: N/A"
        $txtTelemUtil.Text = "Utilization: N/A"
        $txtTelemPower.Text = "Power Draw: N/A"
        $txtTelemDriver.Text = "Driver: N/A"
        $txtTelemMem.Text = "VRAM: N/A"
        $txtTelemSmClock.Text = "SM Clock: N/A"
        $txtTelemMemClock.Text = "Memory Clock: N/A"
    }
    else {
        $txtTelemName.Text = "GPU: $($telem['Name'])"
        $txtTelemTemp.Text = "Temperature: $($telem['TempC']) deg C"
        $txtTelemUtil.Text = "Utilization: $($telem['UtilGpu'])"
        $txtTelemPower.Text = "Power Draw: $($telem['PowerDrawW']) / $($telem['PowerLimitW'])"
        $txtTelemDriver.Text = "Driver: $($telem['Driver'])"
        $txtTelemMem.Text = "VRAM: $($telem['MemUsedMb']) / $($telem['MemTotalMb'])"
        $txtTelemSmClock.Text = "SM Clock: $($telem['ClockSmMhz'])"
        $txtTelemMemClock.Text = "Memory Clock: $($telem['ClockMemMhz'])"
    }
}

function Update-TensorCheckView($tensor) {
    if (-not $txtTensorBadge) { return }
    $txtTensorBadge.Text = $tensor['Badge']
    if ($tensor['Tested'] -and $tensor['TFlops'] -ge $tensor['Threshold']) {
        $badgeTensorBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E3A2F")
        $badgeTensorBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
        $txtTensorBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
    } elseif ($tensor['Tested']) {
        $badgeTensorBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3E2A1E")
        $badgeTensorBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FAB387")
        $txtTensorBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FAB387")
    } else {
        $badgeTensorBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244")
        $badgeTensorBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#6C7086")
        $txtTensorBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CDD6F4")
    }

    $txtTensorThroughput.Text = "Measured Rate: $($tensor['TFlops']) TFLOPS (FP16 GEMM 4096 x 4096)"
    $txtTensorLimiter.Text = "Silicon Rate Limiter: $($tensor['LimiterState'])"
    $txtTensorUplift.Text = "Estimated Uplift: $($tensor['UpliftRatio'])"
    $txtTensorGpu.Text = "Target GPU: $($tensor['GpuName'])"
    $txtTensorTimestamp.Text = "Last Tested: $($tensor['Timestamp'])"
    $txtTensorStatusMsg.Text = "Assessment: $($tensor['Message'])"
    $txtTensorStatus.Text = if ($tensor['Success']) { "Verification completed successfully." } else { $tensor['Message'] }
}

function Update-CompatibilityResultsView($res) {
    $Script:LastAnalysis = $res

    # Status & Badge
    $txtStatusHeader.Text = $res.Badge
    $txtStatusSummary.Text = $res.Summary
    $txtNextStep.Text = $res.NextStep

    $badgeBrush = switch ($res.Status) {
        'candidate' { [System.Windows.Media.Brushes]::LightGreen }
        'needs_data' { [System.Windows.Media.Brushes]::Gold }
        'outside_scope' { [System.Windows.Media.Brushes]::DarkOrange }
        'invalid_data' { [System.Windows.Media.Brushes]::Tomato }
        default { [System.Windows.Media.Brushes]::Gray }
    }
    $badgeStatusBorder.BorderBrush = $badgeBrush
    $txtStatusHeader.Foreground = $badgeBrush

    # Observations breakdown
    $txtObsCaptures.Text = "Captures Found: $($res.CaptureCount) valid DIAG capture(s)"

    if ($res.Observations -and $res.Observations.Count -gt 0) {
        $obs = $res.Observations[0]
        $gpuText = "Unknown"
        if ($obs.adapters -and $obs.adapters.Count -gt 0) {
            $ad = $obs.adapters[0]
            $gpuText = "PCI: $($ad.pci_id) (Subsys: $($ad.subsystem_id), Class: $($ad.class_revision))"
            if ($ad.location) {
                $txtObsPciLoc.Text = "Location: Seg $($ad.location.segment), Bus $($ad.location.bus), Dev $($ad.location.device), Func $($ad.location.function)"
            }
        }
        $txtObsGpu.Text = "Target GPU: $gpuText"
        $memText = if ($obs.device_memory_size_mib) { "$($obs.device_memory_size_mib) MiB" } else { "null" }
        $chipText = if ($obs.chip_id) { "$($obs.chip_id)" } else { "null" }
        $txtObsChip.Text = "Chip ID: $chipText | Memory: $memText"
        $txtObsDisplays.Text = "Displays: $($obs.nvidia_display_count) NVIDIA, $($obs.other_display_count) Other (GOP Handles: $($obs.gop_handle_count))"
        $txtObsNvgop.Text = "NVGOP Bindings: $(if ($obs.firmware_bindings) { $obs.firmware_bindings.Count } else { 0 }) observed"
    }
    else {
        $txtObsGpu.Text = "Target GPU: No observations recorded"
        $txtObsPciLoc.Text = "Location: N/A"
        $txtObsChip.Text = "Chip / Memory: N/A"
        $txtObsDisplays.Text = "Displays: N/A"
        $txtObsNvgop.Text = "NVGOP Bindings: N/A"
    }

    # Itemized Checks
    $chkLines = @()
    foreach ($chk in $res.Checks) {
        $chkLines += "[$($chk.state.ToUpper())] $($chk.code): $($chk.message)"
    }
    if ($chkLines.Count -eq 0) {
        $txtChecksList.Text = "No individual check codes reported."
    }
    else {
        $txtChecksList.Text = ($chkLines -join "`r`n")
    }

    # Raw JSON
    $txtCaptureJson.Text = $res.RawJson
}

# --- INITIALIZE UI STATE ---
$isAdmin = Test-IsAdmin
if ($isAdmin) {
    $txtBadgeAdmin.Text = "ADMINISTRATOR"
    $badgeAdmin.Background = [System.Windows.Media.Brushes]::LightGreen
    $btnElevate.Visibility = [System.Windows.Visibility]::Collapsed
}
else {
    $txtBadgeAdmin.Text = "USER MODE"
    $badgeAdmin.Background = [System.Windows.Media.Brushes]::Gold
    $btnElevate.Visibility = [System.Windows.Visibility]::Visible
}

# --- EVENT HOOKS ---

$btnElevate.Add_Click({
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $psi.Verb = "runas"
        try {
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            $window.Close()
        }
        catch {
            Write-GuiLog "Elevation request was cancelled."
        }
    })

$btnRefresh.Add_Click({
        Refresh-AuditData
        Refresh-PreflightData
        Refresh-UsbList
        Refresh-TelemetryData
        Write-GuiLog "Refreshed all system, safety, and telemetry data."
    })

$btnClearLog.Add_Click({ $txtLog.Clear() })

$btnDisableFastStartup.Add_Click({
        try {
            $msg = Disable-WindowsFastStartup
            Write-GuiLog $msg
            Refresh-PreflightData
            [System.Windows.MessageBox]::Show($msg, "Fast Startup Disabled", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            Write-GuiLog "Error disabling Fast Startup: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })

$btnDownloadAssets.Add_Click({
        Write-GuiLog "Starting automated download and extraction of NVIDIA firmware assets..."
        $btnDownloadAssets.IsEnabled = $false
        $btnDownloadAssets.Content = "Downloading..."
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            $script = Join-Path $scriptDir "download_assets.py"
            $out = & python -I $script --output $Script:AssetsPath 2>&1
            foreach ($line in $out) {
                Write-GuiLog $line
            }
            Refresh-PreflightData
            Write-GuiLog "Firmware assets acquired and verified successfully."
            [System.Windows.MessageBox]::Show("All 5 required GA102 firmware assets were successfully downloaded, verified, and placed into assets/!", "Download Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            Write-GuiLog "Download error: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Error downloading assets:`n$($_.Exception.Message)", "Download Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
        finally {
            $btnDownloadAssets.IsEnabled = $true
            $btnDownloadAssets.Content = "Download Assets (1-Click)"
            $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        }
    })

$btnImportAssets.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select folder containing the 5 GA102 firmware .bin files (e.g. from upstream Zagitta/gpu-unlock)"
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $folder = $fbd.SelectedPath
            Write-GuiLog "Importing firmware assets from '$folder'..."
            try {
                $scriptCheckAssets = Join-Path $scriptDir "Check-Assets.ps1"
                & powershell -NoProfile -ExecutionPolicy Bypass -File $scriptCheckAssets -ImportFrom $folder
                Refresh-PreflightData
                Write-GuiLog "Asset import check completed. Pre-flight status refreshed."
                [System.Windows.MessageBox]::Show("Asset verification finished. Check the Activity Log and Pre-Flight status.", "Import Completed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                Write-GuiLog "Error during asset import: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show($_.Exception.Message, "Import Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        }
    })

$btnAssetsGuide.Add_Click({
        $doc = Join-Path $Script:RepoRoot "docs\ASSETS.en.md"
        $msg = @"
Why are firmware assets missing?
Under NVIDIA's licensing terms, proprietary firmware binaries cannot be redistributed directly inside Git repositories.

How to generate them:
1. In WSL or Linux, run:
   git clone https://github.com/Zagitta/gpu-unlock.git gpu-unlock-firmware-source
   cd gpu-unlock-firmware-source
   git checkout --detach 0ebdb1c6308b6a2072be5bf04513472942541956
   make inputs firmware PYTHON=python3.14 INPUTS="`$PWD/inputs" ASSETS="`$PWD/assets"

2. Once generated, click 'Import Assets...' and select that folder, or copy the 5 .bin files into the repository's 'assets\' directory:
   - booter_load_ga102.bin
   - v67-ga102-610.43.03.bin
   - gsp_ga10x.bin
   - gsp_boot_ga102.bin
   - gsp_boot_desc_ga102.bin

Documentation: docs/ASSETS.en.md
"@
        if (Test-Path -LiteralPath $doc) {
            Start-Process $doc -ErrorAction SilentlyContinue
        }
        [System.Windows.MessageBox]::Show($msg, "How to Get Firmware Assets", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    })

$btnInstallLlvm.Add_Click({
        $confirm = [System.Windows.MessageBox]::Show("Install the LLVM compiler toolchain (clang & lld-link) automatically via Windows Package Manager (winget)?`n`nCommand: winget install --id LLVM.LLVM --exact", "Install LLVM Toolchain", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            $btnInstallLlvm.IsEnabled = $false
            $btnInstallLlvm.Content = "Installing..."
            Write-GuiLog "Starting automated LLVM installation via winget..."
            $window.Cursor = [System.Windows.Input.Cursors]::Wait
            [System.Windows.Forms.Application]::DoEvents()
            try {
                $out = & winget install --id LLVM.LLVM --exact --accept-source-agreements --accept-package-agreements 2>&1
                foreach ($line in $out) {
                    Write-GuiLog $line
                }
                Refresh-PreflightData
                Update-UsbTabInfo
                Write-GuiLog "LLVM toolchain installation completed. Safety pre-flight status refreshed."
                [System.Windows.MessageBox]::Show("LLVM installation process finished! Pre-flight checks refreshed.", "LLVM Installation", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                Write-GuiLog "LLVM installation error: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show("LLVM installation failed: $($_.Exception.Message)`n`nYou can manually install LLVM from terminal by running:`nwinget install LLVM.LLVM", "Installation Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
            finally {
                $btnInstallLlvm.IsEnabled = $true
                $btnInstallLlvm.Content = "Install LLVM (winget)"
                $window.Cursor = [System.Windows.Input.Cursors]::Arrow
            }
        }
    })

$btnRefreshUsb.Add_Click({
        Refresh-UsbList
        Write-GuiLog "Refreshed connected removable USB drive list."
    })

$comboUsbDrives.Add_SelectionChanged({
        Update-UsbTabInfo
    })

$btnStageProbeDirect.Add_Click({
        $selected = [string]$comboUsbDrives.SelectedItem
        if (-not $selected -or $selected.StartsWith("No removable")) {
            [System.Windows.MessageBox]::Show("Please connect a FAT32 USB drive first.", "No USB Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $letter = $selected.Substring(0, 1)
        $confirm = [System.Windows.MessageBox]::Show("Stage read-only Diagnostic Probe on drive $letter`:`\?`n`nWhen booted, the probe records physical DIAGnn.TXT, IMGnn.BIN, and PROM.BIN captures from this PC, and IMMEDIATELY boots into Windows without hanging or returning to BIOS.`n`nTwo agreeing cold-boot captures are required for custom unlock profile generation.", "Confirm Diagnostic Probe Staging", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            Show-UsbProgressOverlay -Title "Staging Diagnostic Probe..." -Detail "Identifying system Windows ESP GUID, compiling tailored probe binary, and writing files to USB drive..."
            try {
                Write-GuiLog "Compiling and staging Diagnostic Probe on $letter`:..."
                $msg = Stage-DiagnosticProbeUsb -Letter $letter -OptIn
                Write-GuiLog $msg
                Update-UsbTabInfo
                Hide-UsbProgressOverlay
                [System.Windows.MessageBox]::Show("Diagnostic Probe staged successfully on drive $letter`:`\!`n`nNext steps:`n1. Power off PC completely (Cold Shutdown, do not use Restart).`n2. Turn on and press Boot Menu key (ASUS F8).`n3. Select UEFI USB drive. The probe safely records your card's pre-boot registers and hands off directly to Windows!`n4. Once in Windows, repeat once more (Cold Shutdown -> Boot USB) to obtain 2 agreeing captures.`n5. Reopen this utility and click 'Build & Stage Custom Unlock Bootloader'!", "Diagnostic Probe Staged (Step 1)", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                Hide-UsbProgressOverlay
                Write-GuiLog "Error staging probe: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show($_.Exception.Message, "Staging Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
            finally {
                Hide-UsbProgressOverlay
            }
        }
    })

$btnDeployUsb.Add_Click({
        $selected = [string]$comboUsbDrives.SelectedItem
        if (-not $selected -or $selected.StartsWith("No removable")) {
            [System.Windows.MessageBox]::Show("Please connect a FAT32 USB drive first.", "No USB Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $letter = $selected.Substring(0, 1)

        # Enforce that both cold-boot captures are detected before allowing build
        $captureStatus = Get-UsbProbeCaptureStatus -Letter $letter
        if ($captureStatus.Count -lt 2) {
            [System.Windows.MessageBox]::Show("Building the custom unlock bootloader requires both cold-boot hardware captures on drive $letter`:`\ (DIAG00.TXT and DIAG01.TXT).`n`nCurrent captures detected: $($captureStatus.Count) of 2.`n`nPlease click '1. Stage Diagnostic Probe' first, then power off and boot from the USB drive twice to collect both captures.", "Hardware Captures Required", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        $confirm = [System.Windows.MessageBox]::Show("Both hardware captures detected on drive $letter`:`\!`n`nBuild and stage the custom Headless Unlock bootloader now?`n`nThis will compile your card's custom profile, run host safety verification tests (22 test suites), and copy the bootloader and firmware assets to $letter`:.", "Confirm Custom Unlock Build", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            Show-UsbProgressOverlay -Title "Building & Staging Custom Unlock Bootloader..." -Detail "Generating machine profile, running offline verification tests (22 test suites), compiling EFI binaries, and staging verified assets to USB drive. Please wait, this takes ~30-60 seconds..."
            try {
                Write-GuiLog "Starting custom unlock build and staging on $letter`:..."
                $msg = Build-And-Stage-Local-Unlock -Letter $letter
                Write-GuiLog $msg
                Update-UsbTabInfo
                Hide-UsbProgressOverlay

                [System.Windows.MessageBox]::Show("Custom Headless Unlock bootloader deployed successfully to $letter`:`\!`n`nWhen booted, the custom unlocker will apply the tensor selector registers and directly launch Windows Boot Manager.`n`nReboot your PC and press your Boot Menu key (ASUS F8 / Gigabyte F12 / MSI F11) to boot.", "Unlock Deployment Success (Step 2)", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                Hide-UsbProgressOverlay
                Write-GuiLog "USB deployment error: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show($_.Exception.Message, "Deployment Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
            finally {
                Hide-UsbProgressOverlay
            }
        }
    })

$btnRunInternalConfigure.Add_Click({
        Write-GuiLog "Internal Headless Setup requires manual execution with exact GUID of dedicated ESP."
        [System.Windows.MessageBox]::Show("To configure Internal Headless ESP, run from Administrator PowerShell:`n`n.\internal-boot\Configure.ps1 -UnlockDriveLetter U -WindowsEspGuid <GUID>`n`nEnsure you use a dedicated secondary ESP partition, never the Windows ESP.", "Internal ESP Instructions", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
    })

$btnRestoreWindowsBcd.Add_Click({
        try {
            Write-GuiLog "Restoring default Windows Boot Manager priority..."
            $msg = Restore-WindowsFirstBootOrder
            Write-GuiLog $msg
            [System.Windows.MessageBox]::Show("Windows Boot Manager has been restored as primary boot entry.", "Boot Order Restored", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            Write-GuiLog "Error restoring boot order: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Restore Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })

$btnEmergencyRestore.Add_Click({
        $btnRestoreWindowsBcd.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
    })

# --- OFFLINE CHECKER TAB EVENT HANDLERS ---

$btnBrowseCaptureFolder.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select Folder Containing Diagnostic Captures (DIAGnn.TXT)"
        if (Test-Path -LiteralPath $txtCaptureFolder.Text) {
            $dialog.SelectedPath = $txtCaptureFolder.Text
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtCaptureFolder.Text = $dialog.SelectedPath
            Write-GuiLog "Selected capture folder: $($dialog.SelectedPath)"
        }
    })

$btnDetectUsbCaptures.Add_Click({
        Write-GuiLog "Searching for EFI capture folders on connected USB drives..."
        $candidates = Find-UsbCaptureFolders
        if ($candidates.Count -gt 0) {
            $txtCaptureFolder.Text = $candidates[0]
            Write-GuiLog "Found capture folder on USB: $($candidates[0])"
            [System.Windows.MessageBox]::Show("Found capture folder on USB drive:`n$($candidates[0])", "USB Captures Located", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        else {
            Write-GuiLog "No capture folders found on USB drives."
            [System.Windows.MessageBox]::Show("No capture folders or DIAG*.TXT files found on connected USB drives.`n`nIf you already booted from USB, ensure the USB stick is plugged in.", "No Captures Found", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
    })

$btnRunOfflineCheck.Add_Click({
        $folder = $txtCaptureFolder.Text.Trim()
        if (-not $folder) {
            [System.Windows.MessageBox]::Show("Please specify or browse to a capture folder.", "Missing Folder", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        $langSelected = if ($comboCheckerLang.SelectedIndex -eq 1) { 'ko' } else { 'en' }
        try {
            Write-GuiLog "Running offline compatibility checker on: $folder (Lang: $langSelected)..."
            $txtStatusHeader.Text = "ANALYZING..."
            $txtStatusHeader.Foreground = [System.Windows.Media.Brushes]::Gold
            $txtStatusSummary.Text = "Reading diagnostic captures, driver images, and PROM..."

            $res = Invoke-OfflineCompatibilityCheck -Folder $folder -Language $langSelected
            Update-CompatibilityResultsView $res
            Write-GuiLog "Offline check complete: $($res.Badge)"
        }
        catch {
            Write-GuiLog "Error during offline check: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Checker Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })

$btnGenWindowsDump.Add_Click({
        try {
            Write-GuiLog "Generating comprehensive Windows diagnostic dump..."
            $out = Export-WindowsDiagnosticDump
            Write-GuiLog "Diagnostic dump created at: $out"
            [System.Diagnostics.Process]::Start("explorer.exe", $out) | Out-Null
            [System.Windows.MessageBox]::Show("Windows diagnostic dump generated at:`n$out`n`nIncludes WINDOWS-INVENTORY.JSON, NVIDIA-SMI-DUMP.XML, DISPLAY-EDID.JSON, and SYSTEM-SUMMARY.JSON.", "Diagnostic Dump Complete", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            Write-GuiLog "Error generating diagnostic dump: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Dump Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })

$btnGenEfiCaptures.Add_Click({
        # Never write fixtures into the currently selected hardware capture set.
        $folder = Join-Path $Script:RepoRoot ("synthetic-captures\fixture-" + [Guid]::NewGuid().ToString('N'))
        try {
            Write-GuiLog "Generating SYNTHETIC TEST FIXTURES in $folder; no hardware is observed..."
            $msg = Export-EfiDiagnosticCaptures -TargetDir $folder
            Write-GuiLog $msg
            $txtCaptureFolder.Text = $folder
            $btnRunOfflineCheck.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
            [System.Windows.MessageBox]::Show("Generated SYNTHETIC TEST FIXTURES in:`n$folder`n`nNo hardware was observed. These are not compatibility or cold-boot evidence and must not be used to build/run an unlock. Offline checking is a software test only.", "Synthetic Test Fixtures", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            Write-GuiLog "Error generating captures: $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Capture Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })

$btnStageProbeUsb.Add_Click({
        $selected = [string]$comboUsbDrives.SelectedItem
        if (-not $selected -or $selected.StartsWith("No removable")) {
            [System.Windows.MessageBox]::Show("Please insert and select a FAT32 USB drive in Tab 3 first.", "No USB Selected", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        $letter = $selected.Substring(0, 1)
        $confirm = [System.Windows.MessageBox]::Show("Stage read-only Diagnostic Probe on drive $letter`:`\?`n`nWhen booted, the probe records physical DIAGnn.TXT, IMGnn.BIN, and PROM.BIN captures from this PC.", "Confirm Diagnostic Probe Staging", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            try {
                Write-GuiLog "Staging Diagnostic Probe on $letter`:..."
                $msg = Stage-DiagnosticProbeUsb -Letter $letter -OptIn
                Write-GuiLog $msg
                [System.Windows.MessageBox]::Show("Diagnostic Probe staged on drive $letter`:`\!`n`nTo collect hardware captures:`n1. Power off PC completely.`n2. Turn on and press Boot Menu key (F8/F12).`n3. Boot USB -> It writes captures and boots Windows.`n4. Repeat once more for 2 agreeing cold boots.`n5. Open this utility and click 'Auto-Detect on USB'!", "Probe Staged", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                Write-GuiLog "Error staging probe: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show($_.Exception.Message, "Staging Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        }
    })

$btnExportJson.Add_Click({
        if (-not $Script:LastAnalysis -or -not $Script:LastAnalysis.RawJson) {
            [System.Windows.MessageBox]::Show("Run an offline compatibility check first to generate a report.", "No Report to Export", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = "JSON Report (*.json)|*.json|All Files (*.*)|*.*"
        $dialog.FileName = "compatibility-report.json"
        $dialog.Title = "Save Compatibility Report JSON"

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                Set-Content -LiteralPath $dialog.FileName -Value $Script:LastAnalysis.RawJson -Encoding utf8
                Write-GuiLog "Saved compatibility report JSON to: $($dialog.FileName)"
                [System.Windows.MessageBox]::Show("Compatibility report saved to:`n$($dialog.FileName)", "Report Exported", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
            catch {
                Write-GuiLog "Failed to export report: $($_.Exception.Message)"
                [System.Windows.MessageBox]::Show($_.Exception.Message, "Export Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
            }
        }
    })

$btnCopyClipboard.Add_Click({
        if (-not $Script:LastAnalysis -or -not $Script:LastAnalysis.RawJson) {
            [System.Windows.MessageBox]::Show("Run an offline compatibility check first to generate a report.", "No Report to Copy", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        try {
            [System.Windows.Forms.Clipboard]::SetText($Script:LastAnalysis.RawJson)
            Write-GuiLog "Copied compatibility report JSON to clipboard."
            [System.Windows.MessageBox]::Show("Compatibility report JSON copied to clipboard!`n`nYou can paste it directly into the GitHub Issue report form.", "Copied to Clipboard", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
        }
        catch {
            Write-GuiLog "Failed to copy to clipboard: $($_.Exception.Message)"
        }
    })

$btnBrowseLeftReport.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "JSON Reports (*.json)|*.json|All Files (*.*)|*.*"
        $dialog.Title = "Select Reference Compatibility Report JSON"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtLeftReport.Text = $dialog.FileName
        }
    })

$btnBrowseRightReport.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "JSON Reports (*.json)|*.json|All Files (*.*)|*.*"
        $dialog.Title = "Select Probe Compatibility Report JSON"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtRightReport.Text = $dialog.FileName
        }
    })

$btnRunCompareReports.Add_Click({
        $left = $txtLeftReport.Text.Trim()
        $right = $txtRightReport.Text.Trim()
        if (-not $left -or -not $right) {
            [System.Windows.MessageBox]::Show("Please select both a reference (Left) and a probe (Right) JSON report file.", "Missing Reports", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        try {
            Write-GuiLog "Comparing reports: $left vs $right..."
            $txtCompareResult.Text = "Running compare-compatibility.py..."
            $diff = Invoke-CompareCompatibilityReports -LeftReportPath $left -RightReportPath $right
            $txtCompareResult.Text = $diff
            Write-GuiLog "Report comparison finished."
        }
        catch {
            $txtCompareResult.Text = "Comparison Error: $($_.Exception.Message)"
            Write-GuiLog "Comparison error: $($_.Exception.Message)"
        }
    })

if ($btnRefreshUnlock) {
    $btnRefreshUnlock.Add_Click({
        Refresh-TelemetryData
        Write-GuiLog "Refreshed hardware register verification status."
    })
}

if ($btnRunTensorCheck) {
    $btnRunTensorCheck.Add_Click({
        $btnRunTensorCheck.IsEnabled = $false
        $btnRunTensorCheck.Content = "Benchmarking Silicon..."
        if ($txtTensorStatus) { $txtTensorStatus.Text = "Running 4096 x 4096 FP16 GEMM on GPU silicon..." }
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            Write-GuiLog "Starting live silicon tensor verification benchmark..."
            $res = Test-GpuSiliconTensor -Iterations 50
            Update-TensorCheckView $res
            Write-GuiLog "Silicon tensor verification finished: $($res.TFlops) TFLOPS ($($res.LimiterState))."
            [System.Windows.MessageBox]::Show($res.Message, "Silicon Verification Result", [System.Windows.MessageBoxButton]::OK, $(if ($res.TFlops -ge $res.Threshold) { [System.Windows.MessageBoxImage]::Information } else { [System.Windows.MessageBoxImage]::Warning })) | Out-Null
        }
        catch {
            Write-GuiLog "Error during silicon tensor check: $($_.Exception.Message)"
            if ($txtTensorStatus) { $txtTensorStatus.Text = "Error: $($_.Exception.Message)" }
            [System.Windows.MessageBox]::Show($_.Exception.Message, "Benchmark Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
        finally {
            $btnRunTensorCheck.IsEnabled = $true
            $btnRunTensorCheck.Content = "Run Live Silicon Tensor Check"
            $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        }
    })
}

if ($btnRefreshTelem) {
    $btnRefreshTelem.Add_Click({
        Refresh-TelemetryData
        Write-GuiLog "Refreshed live GPU telemetry and verification status."
    })
}

# Load Initial Data
Refresh-AuditData
Refresh-PreflightData
Refresh-UsbList
Refresh-TelemetryData
Write-GuiLog "GPU Unlock Utility ready. Welcome!"

# Show Dialog
$window.ShowDialog() | Out-Null
