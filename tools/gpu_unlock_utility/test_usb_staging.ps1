# Mock regression tests for USB staging safety requirements.
# Validates native Windows PowerShell behavior without modifying any real disk or system partition.
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir '..\..'))
$utilityScript = Join-Path $scriptDir 'GpuUnlockUtility.ps1'

# Parse utility script AST to extract Stage-DiagnosticProbeUsb and Deploy-ToUsb definitions
$ast = [System.Management.Automation.Language.Parser]::ParseFile($utilityScript, [ref]$null, [ref]$null)
$funcs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

$stageProbeAst = $funcs | Where-Object { $_.Name -eq 'Stage-DiagnosticProbeUsb' } | Select-Object -First 1
$deployUsbAst = $funcs | Where-Object { $_.Name -eq 'Deploy-ToUsb' } | Select-Object -First 1

if (-not $stageProbeAst -or -not $deployUsbAst) {
    throw "Failed to locate Stage-DiagnosticProbeUsb or Deploy-ToUsb in $utilityScript"
}

# Sandbox temp root
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("usb-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    $mockRoot = Join-Path $tempDir 'mock_drive'
    New-Item -ItemType Directory -Path $mockRoot -Force | Out-Null
    New-PSDrive -Name 'Z' -PSProvider FileSystem -Root $mockRoot | Out-Null

    # Define mock state
    $global:MockDisk = [pscustomobject]@{ BusType = 'USB'; IsBoot = $false; Number = 1 }
    $global:MockPart = [pscustomobject]@{ IsSystem = $false; IsBoot = $false; DiskNumber = 1; Guid = [guid]'22222222-2222-2222-2222-222222222222' }
    $global:MockVol = [pscustomobject]@{ FileSystem = 'FAT32' }
    $global:SystemEspGuid = [guid]'11111111-1111-1111-1111-111111111111'
    $global:Script = @{ RepoRoot = $repoRoot }

    # Define mocks in script scope
    function global:Get-Disk { param($Number) return $global:MockDisk }
    function global:Get-Partition { param($DriveLetter, $DiskNumber) return $global:MockPart }
    function global:Get-Volume { param($DriveLetter) return $global:MockVol }
    function global:Get-SystemWindowsEspGuid { return $global:SystemEspGuid }
    function global:Get-ClangToolchain { return @{ Available = $true; Clang = 'clang'; LldLink = 'lld-link' } }
    function global:Get-UsbProbeCaptureStatus { param($Letter) return @{ Count = 0 } }
    function global:Get-GpuHardwareInfo { return @{ GPUs = @(); BoardProduct = 'TEST'; BIOSVersion = '1.0' } }

    # Load functions
    Invoke-Expression $stageProbeAst.Extent.Text
    Invoke-Expression $deployUsbAst.Extent.Text

    $passCount = 0

    function Assert-Throws([scriptblock]$Block, [string]$Pattern, [string]$TestName) {
        $threw = $false
        $msg = ""
        try {
            & $Block
        }
        catch {
            $threw = $true
            $msg = $_.Exception.Message
        }
        if (-not $threw) {
            throw "FAIL [$TestName]: Expected exception matching '$Pattern', but no exception was thrown."
        }
        if ($msg -notmatch $Pattern) {
            throw "FAIL [$TestName]: Expected pattern '$Pattern' but got message: '$msg'"
        }
        Write-Host "  PASS: $TestName" -ForegroundColor Green
        $script:passCount++
    }

    Write-Host "Running USB Staging Safety Regression Tests..." -ForegroundColor Cyan

    # 1. Staging without -OptIn is refused
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z'
    } "explicit opt-in" "Refuses staging without -OptIn"

    # 2. Non-existent drive root is refused
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'X' -OptIn
    } "does not exist" "Refuses non-existent drive root"

    # 3. Non-USB bus type (e.g. NVMe, SATA) is rejected
    $global:MockDisk.BusType = 'NVMe'
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "not a FAT32 USB data stick" "Rejects NVMe/SATA internal disk target"
    $global:MockDisk.BusType = 'USB'

    # 4. System partition is rejected
    $global:MockPart.IsSystem = $true
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "not a FAT32 USB data stick" "Rejects system partition target"
    $global:MockPart.IsSystem = $false

    # 5. Boot disk is rejected
    $global:MockDisk.IsBoot = $true
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "not a FAT32 USB data stick" "Rejects boot disk target"
    $global:MockDisk.IsBoot = $false

    # 6. Boot partition is rejected
    $global:MockPart.IsBoot = $true
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "is a boot partition; staging refused" "Rejects boot partition target"
    $global:MockPart.IsBoot = $false

    # 7. Mounted system Windows ESP partition is rejected
    $global:MockPart.Guid = $global:SystemEspGuid
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "is the system Windows ESP partition; staging refused" "Rejects mounted system Windows ESP partition"
    $global:MockPart.Guid = [guid]'22222222-2222-2222-2222-222222222222'

    # 8. Non-FAT32 file system is rejected
    $global:MockVol.FileSystem = 'NTFS'
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "not a FAT32 USB data stick" "Rejects NTFS formatted volume"
    $global:MockVol.FileSystem = 'FAT32'

    # 9. Existing destination BOOTX64.EFI is refused (no overwrite, no backup-replace)
    $efiBootDir = Join-Path $mockRoot 'EFI\BOOT'
    New-Item -ItemType Directory -Path $efiBootDir -Force | Out-Null
    $bootFile = Join-Path $efiBootDir 'BOOTX64.EFI'
    [System.IO.File]::WriteAllBytes($bootFile, [byte[]]@(1, 2, 3, 4))
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "Destination file already exists" "Refuses existing BOOTX64.EFI destination file"
    Remove-Item -LiteralPath $bootFile -Force

    # 10. Existing destination README-PROBE.TXT is refused
    $readmeProbe = Join-Path $mockRoot 'README-PROBE.TXT'
    [System.IO.File]::WriteAllText($readmeProbe, "EXISTING")
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "Destination file already exists" "Refuses existing README-PROBE.TXT destination file"
    Remove-Item -LiteralPath $readmeProbe -Force

    # 11. Existing destination RTX3090-UNLOCK\README.TXT is refused
    $payloadDir = Join-Path $mockRoot 'RTX3090-UNLOCK'
    New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
    $readmePayload = Join-Path $payloadDir 'README.TXT'
    [System.IO.File]::WriteAllText($readmePayload, "EXISTING")
    Assert-Throws {
        Stage-DiagnosticProbeUsb -Letter 'Z' -OptIn
    } "Destination file already exists" "Refuses existing payload README.TXT destination file"
    Remove-Item -LiteralPath $readmePayload -Force

    # 12. Deploy-ToUsb does not silently stage probe when captures are missing
    Assert-Throws {
        Deploy-ToUsb -Letter 'Z'
    } "Please stage and boot the Diagnostic Probe USB explicitly first" "Deploy-ToUsb refuses silent probe staging when captures missing"

    # 13. Deploy-ToUsb validates USB target and rejects system partition
    $global:MockPart.IsSystem = $true
    Assert-Throws {
        Deploy-ToUsb -Letter 'Z'
    } "not a FAT32 USB data stick" "Deploy-ToUsb rejects system partition"
    $global:MockPart.IsSystem = $false

    Write-Host "`nAll $passCount USB staging safety regression tests PASSED.`n" -ForegroundColor Green
}
finally {
    Remove-PSDrive -Name 'Z' -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
