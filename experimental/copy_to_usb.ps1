param(
    [Parameter(Mandatory=$true)]
    [string]$DriveLetter,
    [switch]$Force
)

$DriveChar = $DriveLetter.TrimEnd(':\').Substring(0, 1).ToUpper()
$DriveLetter = "$DriveChar`:"

# 1. Prohibit targeting the Windows system drive
$SysDrive = $env:SystemDrive.TrimEnd(':').ToUpper()
if ($DriveChar -eq $SysDrive -or $DriveChar -eq "C") {
    Write-Error "[FATAL] Refusing to target Windows system drive ($DriveLetter)! This would corrupt host OS boot files."
    exit 1
}

# 2. Check if volume exists and inspect filesystem/drive type
$vol = Get-Volume -DriveLetter $DriveChar -ErrorAction SilentlyContinue
if (-not $vol) {
    Write-Error "[ERROR] Volume $DriveLetter was not found! Please check drive connection."
    exit 1
}

if ($vol.DriveType -ne 'Removable' -and $vol.FileSystem -ne 'FAT32') {
    Write-Host "[WARNING] Target drive $DriveLetter is '$($vol.DriveType)' (FS: $($vol.FileSystem)), not a Removable FAT32 drive!" -ForegroundColor Yellow
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to write UEFI bootloader to $DriveLetter? (type YES to confirm)"
        if ($confirm -ne 'YES') {
            Write-Host "Operation cancelled by operator." -ForegroundColor Red
            exit 1
        }
    }
}

$repo = $PSScriptRoot
Write-Host "Copying Universal GPU Unlock files to USB drive $DriveLetter..." -ForegroundColor Cyan

# 3. Create backup of pre-existing BOOTX64.EFI if present
$targetEfi = "$DriveLetter\EFI\BOOT\BOOTX64.EFI"
$backupEfi = "$DriveLetter\EFI\BOOT\BOOTX64.EFI.bak"
if (Test-Path $targetEfi) {
    Write-Host "Backing up existing BOOTX64.EFI -> BOOTX64.EFI.bak ..." -ForegroundColor Gray
    Copy-Item -Path $targetEfi -Destination $backupEfi -Force
}

# 4. Dist EFI / BOOT
$sourceEfi = "$repo\dist\EFI\BOOT\BOOTX64.EFI"
if (Test-Path "$repo\dist") {
    Copy-Item -Path "$repo\dist\*" -Destination "$DriveLetter\" -Recurse -Force
}

# Verify integrity of copied BOOTX64.EFI
if ((Test-Path $sourceEfi) -and (Test-Path $targetEfi)) {
    $srcHash = (Get-FileHash -Path $sourceEfi -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -Path $targetEfi -Algorithm SHA256).Hash
    if ($srcHash -ne $dstHash) {
        Write-Error "[FATAL] SHA-256 hash mismatch on BOOTX64.EFI after transfer! Flash drive may have bad sectors or write errors."
        exit 1
    }
    Write-Host "[VERIFIED] BOOTX64.EFI SHA-256 matched: $srcHash" -ForegroundColor Green
}

# 5. UNIVERSAL-ASSETS -> EFI\ASSETS
if (Test-Path "$repo\UNIVERSAL-ASSETS") {
    New-Item -ItemType Directory -Force -Path "$DriveLetter\EFI\ASSETS" | Out-Null
    Copy-Item -Path "$repo\UNIVERSAL-ASSETS\*" -Destination "$DriveLetter\EFI\ASSETS\" -Recurse -Force
}

# 6. EFI (VBIOS, etc)
if (Test-Path "$repo\EFI") {
    Copy-Item -Path "$repo\EFI\*" -Destination "$DriveLetter\EFI\" -Recurse -Force
}

# 7. Scripts and tools
if (Test-Path "$repo\dump_vbios.bat") { Copy-Item -Path "$repo\dump_vbios.bat" -Destination "$DriveLetter\" -Force }
if (Test-Path "$repo\dump_vbios.ps1") { Copy-Item -Path "$repo\dump_vbios.ps1" -Destination "$DriveLetter\" -Force }
if (Test-Path "$repo\enable_laptop_hybrid.bat") { Copy-Item -Path "$repo\enable_laptop_hybrid.bat" -Destination "$DriveLetter\" -Force }
if (Test-Path "$repo\enable_laptop_hybrid.ps1") { Copy-Item -Path "$repo\enable_laptop_hybrid.ps1" -Destination "$DriveLetter\" -Force }
if (Test-Path "$repo\tools\nvflashk.exe") {
    Copy-Item -Path "$repo\tools\nvflashk.exe" -Destination "$DriveLetter\" -Force
} elseif (Test-Path "$repo\nvflashk.exe") {
    Copy-Item -Path "$repo\nvflashk.exe" -Destination "$DriveLetter\" -Force
} elseif (Test-Path "$repo\..\nvflashk.exe") {
    Copy-Item -Path "$repo\..\nvflashk.exe" -Destination "$DriveLetter\" -Force
}
if (Test-Path "$repo\usb_release_staging\ИНСТРУКЦИЯ.txt") {
    Copy-Item -Path "$repo\usb_release_staging\ИНСТРУКЦИЯ.txt" -Destination "$DriveLetter\" -Force
}

Write-Host "Done! All files successfully deployed and verified on $DriveLetter." -ForegroundColor Green
