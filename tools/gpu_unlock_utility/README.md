# Windows GPU UNLOCK - Management & Deployment Utility

The **Windows GPU UNLOCK Management & Deployment Utility** (`gpuunlockutility.ps1`) is a unified, executive GUI and command-line application for the [Windows-GPU-UNLOCK](https://github.com/ahsanumair/Windows-GPU-UNLOCK) project. 

It provides an end-to-end management toolkit for hardware auditing, safety pre-flight verification, offline EFI compatibility analysis, headless USB staging, BCD boot configuration, live GPU telemetry, and instant 1-click emergency recovery.

---

## Table of Contents

- [1. Overview & Architecture](#1-overview--architecture)
- [2. System Requirements & Prerequisites](#2-system-requirements--prerequisites)
- [3. How to Launch](#3-how-to-launch)
  - [Option A: One-Click Batch Launcher (Recommended)](#option-a-one-click-batch-launcher-recommended)
  - [Option B: PowerShell Launcher](#option-b-powershell-launcher)
  - [Option C: Direct Script Invocation](#option-c-direct-script-invocation)
  - [Administrator vs Standard User Mode](#administrator-vs-standard-user-mode)
- [4. Graphical User Interface (GUI) Guide](#4-graphical-user-interface-gui-guide)
  - [Header & Global Controls](#header--global-controls)
  - [Tab 1: System & GPU Audit](#tab-1-system--gpu-audit)
  - [Tab 2: Pre-Flight Safety](#tab-2-pre-flight-safety)
  - [Tab 3: USB Unlock Deployer (Recommended Route)](#tab-3-usb-unlock-deployer-recommended-route)
  - [Tab 4: Internal ESP Setup (Advanced / Optional)](#tab-4-internal-esp-setup-advanced--optional)
  - [Tab 5: Offline Compatibility Checker & Analyser](#tab-5-offline-compatibility-checker--analyser)
  - [Tab 6: Verification & Telemetry](#tab-6-verification--telemetry)
  - [Tab 7: Emergency Recovery](#tab-7-emergency-recovery)
- [5. Command-Line Interface (CLI) Reference](#5-command-line-interface-cli-reference)
  - [CLI Syntax & Parameters](#cli-syntax--parameters)
  - [CLI Action Examples](#cli-action-examples)
- [6. Diagnostic Dumps & Hardware Captures](#6-diagnostic-dumps--hardware-captures)
- [7. Companion Helper Scripts](#7-companion-helper-scripts)
  - [Check-Assets.ps1 (Firmware Integrity & Import)](#check-assetsps1-firmware-integrity--import)
  - [generate_captures.py (Synthetic EFI Captures)](#generate_capturespy-synthetic-efi-captures)
- [8. Recommended End-to-End Walkthrough](#8-recommended-end-to-end-walkthrough)
- [9. Troubleshooting & FAQ](#9-troubleshooting--faq)

---

## 1. Overview & Architecture

The utility orchestrates all components of the GPU unlock deployment lifecycle safely within Windows:

```
+-----------------------------------------------------------------------------------+
|                        Windows GPU UNLOCK Utility GUI / CLI                       |
+-----------------------------------------------------------------------------------+
       |                       |                      |                     |
       v                       v                      v                     v
 [System & GPU Audit]    [Safety Checks]       [USB / ESP Stager]   [Offline Checker]
 - Win32 WMI / CIM       - Secure Boot         - FAT32 Auto-Detect  - DIAGnn.TXT
 - GA102/104/106 Detect  - BitLocker C: State  - Release BOOTX64    - IMGnn / PROM
 - PCIe VEN/DEV/SUBSYS   - Fast Startup Toggle - Assets Packaging   - Python Analysis
       |                       |                      |                     |
       +-----------------------+----------------------+---------------------+
                                       |
                                       v
                      [Verification & Telemetry]
                      - nvidia-smi Live Stats
                      - cuBLAS 4096 Uplift Protocol
                      - Emergency 1-Click BCD Revert
```

- **Read-Only Safety First**: Hardware probing and capture checks are strictly non-destructive. No firmware is written to the GPU ROM.
- **Pre-Boot Selector Modulation**: Unlocks full tensor performance on NVIDIA Ampere GPUs by configuring Falcon/GSP selector registers (`SS0` and `SS1`) before the Windows display driver initializes.
- **Fail-Safe Recovery**: Instant restoration of stock Windows Boot Manager (`{bootmgr}`) at any time.

---

## 2. System Requirements & Prerequisites

### Supported Operating Systems
- **Windows 10 (64-bit)** or **Windows 11 (64-bit)**
- **Windows Server 2022+**
- System must boot in **UEFI Mode** with a **GPT** partition table (Legacy MBR boot mode is not supported).

### Supported Hardware
- **NVIDIA Ampere Architecture GPUs**:
  - NVIDIA GeForce RTX 3060 (GA104 & GA106)
  - NVIDIA GeForce RTX 3070 & RTX 3070 Ti (GA104)
  - NVIDIA GeForce RTX 3080 10GB & 12GB (GA102)
  - NVIDIA GeForce RTX 3090 & RTX 3090 Ti (GA102)
- **Removable Media**:
  - One USB Flash Drive (1 GiB or larger), formatted as **FAT32**.

### Software Dependencies
- **PowerShell 5.1** (built into Windows) or **PowerShell 7+**
- **Python 3.8+** (required for offline capture validation and report comparison; must be on your system `PATH`)
- **NVIDIA Display Driver** with `nvidia-smi` available (standard with official NVIDIA drivers)
- **LLVM / Clang Toolchain (Optional for Probe, Required for Custom Unlock Build)**:
  - Required if building a machine-specific unlock bootloader via **Build & Stage Custom Unlock Bootloader** (`clang.exe` and `lld-link.exe`).
  - Automatically discovered in `C:\Program Files\LLVM\bin\` or `C:\TOOLS\LLVM20\bin\`.
  - Install via Windows Package Manager: `winget install LLVM.LLVM`.
  - *Note: Pre-compiled read-only diagnostic probes do NOT require LLVM.*

---

## 3. How to Launch

The repository provides multiple convenient entry points to start the utility depending on your workflow:

### Option A: One-Click Batch Launcher (Recommended)
Double-click `Launch-Utility.cmd` located in the `tools` folder (or invoke from terminal):

```bat
.\tools\Launch-Utility.cmd
```

1. If run as a standard user, it presents a menu:
   ```text
   [1] Launch with Administrator Elevation (Recommended)
   [2] Launch in User Mode (Read-only diagnostics)
   ```
2. Choosing `1` prompts Windows UAC for elevation and opens the full GUI with administrative privileges enabled.

### Option B: PowerShell Launcher
Run the PowerShell wrapper script from the `tools` folder:

```powershell
.\tools\Launch-Utility.ps1
```

To run in CLI mode using the launcher:
```powershell
.\tools\Launch-Utility.ps1 -Cli -Action Audit
```

### Option C: Direct Script Invocation
You can launch the utility directly from a PowerShell console:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\gpu_unlock_utility\GpuUnlockUtility.ps1
```

### Administrator vs Standard User Mode
| Capability | Standard User | Administrator |
| :--- | :---: | :---: |
| System & GPU Hardware Audit | Yes | Yes |
| Offline Compatibility Analysis (`DIAG*.TXT`) | Yes | Yes |
| Generate Windows Diagnostic Dumps | Yes | Yes |
| Stage Unlock / Probe Payload to USB | Yes | Yes |
| Disable Windows Fast Startup | No | Yes |
| Inspect BitLocker Key Protection State | Partial | Full |
| Configure Internal BCD Boot Entries | No | Yes |
| One-Click UEFI NVRAM Boot Order Restore | No | Yes |

> [!TIP]
> Always launch as **Administrator** if you plan to stage boot configurations, toggle Fast Startup, or modify UEFI BCD entries.

---

## 4. Graphical User Interface (GUI) Guide

The modern dark-themed WPF interface is structured into seven distinct tabs along with a live status bar and execution console.

```
+------------------------------------------------------------------------------------+
|  Windows GPU UNLOCK - Management & Deployment Utility             [ADMIN] [Refresh]|
+------------------------------------------------------------------------------------+
| [System Audit] [Safety] [USB Deploy] [ESP Setup] [Checker] [Telemetry] [Recovery]  |
+------------------------------------------------------------------------------------+
|                                                                                    |
|                               Active Tab Content Area                              |
|                                                                                    |
+------------------------------------------------------------------------------------+
|  Activity & Execution Log                                                  [Clear] |
|  [2026-11-07 11:00:00] System audit completed successfully.                        |
+------------------------------------------------------------------------------------+
```

---

### Header & Global Controls
- **Privilege Badge**: Displays `[ADMINISTRATOR]` (Green) or `[STANDARD USER]` (Yellow).
- **Run as Admin Button**: Visible when not elevated; prompts for immediate UAC elevation.
- **Refresh All Audits**: Re-runs hardware queries, safety audits, and USB detection.
- **Activity & Execution Log**: Bottom console displaying real-time PowerShell output, file operations, and status messages. Click **Clear** to reset the view.

---

### Tab 1: System & GPU Audit
Inspects host platform topology and determines target GPU eligibility:

- **Host Platform Details**: Motherboard manufacturer, board model, BIOS release version, CPU model, and Windows build number.
- **GPU Controller & PCI Details**:
  - Detected GPU model name
  - PCI Vendor ID (`VEN_10DE`), Device ID, Subsystem Vendor/Device
  - Detected architecture (e.g., `GA102 Ampere`, `GA104 Ampere`)
  - Dedicated VRAM size
  - Installed display driver version
- **Determination Banner**: Alerts you if the GPU matches a known fixed configuration profile (such as `b650m-3090fe`, `b660m-3070ti`, `x870-3090ti`) or qualifies for generic USB staging.

---

### Tab 2: Pre-Flight Safety
Before attempting any UEFI boot unlock, six critical safety checks and prerequisites are evaluated:

1. **UEFI Secure Boot**:
   - Status: `[OK]` (Disabled) or `[FAIL]` (Enabled).
   - *Requirement*: Secure Boot must be disabled in your motherboard BIOS because the unlock bootloader is an unsigned custom EFI binary.
2. **Windows Fast Startup (`HiberbootEnabled`)**:
   - Status: `[OK]` (Disabled) or `[WARN]` (Enabled).
   - *Requirement*: Hybrid sleep prevents full PCIe register power cycles. If enabled, click the **Disable Fast Startup** button to toggle it off automatically.
3. **BitLocker C: Encryption**:
   - Status: `[OK]` (Off / Fully Decrypted) or `[WARN]` (Protection On).
   - *Requirement*: Modifying boot chains while BitLocker is active may trigger a recovery key prompt on boot. Back up your BitLocker recovery key or suspend encryption before proceeding.
4. **Pre-Compiled UEFI Bootloader (`BOOTX64.EFI`)**:
   - Status: `[OK]` (Green - Valid) or `[FAIL]` (Red - Missing/Checksum mismatch).
   - Verifies the compiled `release\EFI\BOOT\BOOTX64.EFI` binary against SHA-256 provenance in `release\provenance.json`.
5. **Firmware Asset Files (`assets/*.bin` - GA102 Blobs)**:
   - Status: `[OK]` (Green - 5/5 verified) or `[!]` (Gold - Missing/Incomplete).
   - *Why is this gold initially?* Proprietary NVIDIA firmware binaries cannot legally be redistributed inside public Git repositories (see `docs/ASSETS.en.md`).
   - *Understanding the filenames*: `booter_load_ga102.bin` is **not** an invalid PC bootloader; it is NVIDIA's Falcon microcontroller firmware booter for GA102 GPUs.
   - *Quick Actions*:
     - **Download Assets (1-Click)**: Automated acquisition and checksum verification.
     - **Import Assets...**: Click to choose any folder containing the 5 extracted `.bin` files (e.g. from Downloads). The utility checks all SHA-256 hashes and copies valid files into `assets\`.
     - **How to Get Assets**: Opens `docs/ASSETS.en.md` and displays instructions to generate them using the upstream tool (`make inputs firmware`).
6. **LLVM / Clang Toolchain (`clang.exe` and `lld-link.exe`)**:
   - Status: `[OK]` (Green - Ready) or `[!]` (Gold - Missing).
   - *Requirement*: Required for compiling machine-tailored Headless Unlock bootloaders for non-reference motherboards.
   - *Quick Action*: If missing, an **Install LLVM (winget)** button appears, allowing 1-click installation via Windows Package Manager (`winget install --id LLVM.LLVM --exact`).

---

### Tab 3: USB Unlock Deployer (Recommended Route)
Stages either a standard pre-compiled unlock bootloader or guides you through the intelligent **Two-Step Headless Deployment Workflow** tailored specifically to your PC:

#### Intelligent Route Selection:
- **Standard Proven Profiles**: For reference systems matching proven hardware profiles, clicking **Stage Unlock Files to Selected USB** writes the pre-compiled `BOOTX64.EFI` and firmware assets directly.
- **Headless Single-RTX / Local Profile Route**: If you have a custom or non-reference motherboard (such as ASUS TUF B460, Intel F-series CPUs with no iGPU, or monitors connected directly to the discrete RTX), the utility dynamically displays the **Two-Step Headless Workflow**:
  1. **Step 1: Stage Diagnostic Probe (Embedded ESP GUID)**:
     - Automatically identifies your Windows EFI System Partition (ESP) GUID.
     - Compiles and stages a tailored read-only diagnostic probe (`BOOTX64.EFI`) onto the USB drive.
     - **No BIOS Loops**: Because your Windows ESP GUID is embedded, the probe records pre-boot diagnostic registers and immediately chain-loads `\EFI\Microsoft\Boot\bootmgfw.efi` directly into Windows without dropping into the BIOS setup screen.
     - *Action*: Power off PC completely, boot USB once (F8/F12). Repeat once more to capture two agreeing cold boots.
  2. **Capture Agreement Tracker**:
     - Real-time indicator tracks capture status: `0 of 2`, `1 of 2`, or `2 of 2 complete [READY FOR CUSTOM UNLOCK BUILD]`.
  3. **Step 2: Build & Stage Custom Unlock Bootloader (Conditionally Enabled)**:
     - Automatically disabled (50% opacity with tooltip guidance) until **2 of 2** agreeing cold-boot captures are detected on the target USB drive.
     - Once enabled, compiling unlocks your machine's hardware profile ([`profile-local.h`](../../internal-boot/unlock/profile-local.h)) locked to your exact PCIe BDF address, VBIOS PROM hash, and strap registers.
     - Executes the mandatory 22-suite offline verification harness (`test-profile.ps1`) using LLVM/Clang.
     - Builds the parent loader (`BOOTX64.EFI`) and child unlock binary (`UNLOCK-HEADLESS.EFI`) featuring buffered I/O logging (eliminating USB flush stalls).
     - Copies the verified binaries and firmware assets to `E:\EFI\BOOT\` and `E:\EFI\WindowsGPUUnlock\`.
  4. **Active Progress Overlay**:
     - When either staging the probe or building the custom unlock bootloader, an animated progress overlay appears over the tab informing you of the background compilation/testing status and advising to keep the USB drive connected until complete.

#### One-Time Boot Menu Guide:
- **ASUS**: Press <kbd>F8</kbd> during POST
- **Gigabyte / AORUS**: Press <kbd>F12</kbd> during POST
- **MSI**: Press <kbd>F11</kbd> during POST
- **ASRock**: Press <kbd>F11</kbd> during POST

---

### Tab 4: Internal ESP Setup (Advanced / Optional)
Configures an internal dedicated secondary EFI System Partition (ESP) on internal SSD storage:

> [!WARNING]
> This route is intended for advanced testing only. The partition **must** be a separate dedicated GPT FAT32 partition. **Never overwrite your primary Windows EFI system partition.**

- **Configure Internal Boot Config**: Copies unlock files to the dedicated partition and registers a temporary BCD entry titled `GPU Headless UNLOCK - EXPERIMENTAL`.
- **Restore Windows Boot Priority**: Re-establishes stock Windows Boot Manager as priority #1.

---

### Tab 5: Offline Compatibility Checker & Analyser
Performs read-only inspection of pre-boot EFI capture artifacts (`DIAGnn.TXT`, `IMGnn.BIN`, `PROM.BIN`) using the project's multi-engine analysis suite:

#### How to Run an Analysis:
1. In **Capture Folder**, specify the path where captures are stored (e.g. `D:\RTX3090-UNLOCK` or `C:\captures`).
2. Or click **Auto-Detect on USB** to scan all connected USB drives automatically for EFI capture directories.
3. Choose your preferred output language (`English (en)` or `한국어 (ko)`).
4. Click **Run Offline Compatibility Check**.

#### Output Views:
- **Assessment Badging**:
  - `[CANDIDATE]`: Hardware and display topology match safe criteria. Ready for unlock generation.
  - `[NEEDS DATA]`: Incomplete captures or missing cold-boot capture agreements.
  - `[OUTSIDE SCOPE]`: Hardware or display controller topology outside reviewed envelope.
  - `[INVALID DATA]`: Corrupted or inconsistent dump files.
- **Next Step Guidance**: Contextual recommendations based on the findings.
- **Sub-Tab 1: Structured Observations & Checks**:
  - Detailed hardware breakdown: Target GPU, PCI bus location, chip/memory configuration, NVGOP version, and display controller handles.
  - Itemized checks table showing status for `observations_pass`, `images_pass`, `prom_pass`, etc.
- **Sub-Tab 2: Raw JSON Report**: Full Format-2 JSON report.
- **Export & Clipboard Buttons**:
  - **Export Report JSON...**: Saves the report to a `.json` file.
  - **Copy JSON to Clipboard**: Copies formatted JSON to paste into a GitHub issue report.

#### Report Comparison Suite:
Located in the expandable panel at the bottom of Tab 5:
1. Browse or enter **Left (Reference)** JSON report.
2. Browse or enter **Right (Probe)** JSON report.
3. Click **Compare Selected Reports** to generate an itemized comparison matrix showing `same`, `different`, or `unavailable` attributes.

---

### Tab 6: Verification & Telemetry
After booting through the unlock bootloader into Windows, use this tab to verify the unlock through a robust **dual-check verification architecture** and inspect real-time GPU health:

#### 1. CHECK 1: Hardware Register Verification (UEFI NVRAM & Bootloader Session)
- **Direct Hardware Register Verification**: Confirms that strapping registers (`SS0 = 0x88888888 | SS1 = 0x00000008` in unlocked state vs. `SS0 = 0x25204022 | SS1 = 0x7` in stock state) were successfully latched during the boot transaction.
- **UEFI NVRAM Runtime Variable Priority**: Queries the UEFI runtime environment variable `GpuUnlockState` directly from firmware memory via Win32 `GetFirmwareEnvironmentVariableW`, allowing hardware register verification even if the boot USB stick has been unplugged.
- **Pre-Boot Bootloader Session Log Fallback**: Gracefully falls back to reading `RTX3090-UNLOCK/AUTO*/REPORT.TXT` if NVRAM export was not present or if Windows is run without administrative privilege.
- **Operating State & Profile**: Displays active profile (e.g. `entryLatchedSs1Full`) and state (`Active & Unlocked (Workstation/vGPU Straps Latched)`).
- **PCIe FLR & Handoff**: Confirms that PCIe Function-Level Reset (FLR) completed cleanly (`Status = 0, Clean = 1`) and Windows handoff transferred smoothly to `\EFI\Microsoft\Boot\bootmgfw.efi`.
- **Refresh Control**: Click **Refresh Hardware Registers** to query live NVRAM / session status on demand.

#### 2. CHECK 2: Silicon Functional Verification (Live Tensor Core Benchmark)
- **Direct Silicon Benchmark**: Executes real-time 4096 x 4096 FP16 GEMM matrix multiplication directly on GPU silicon (via PyTorch CUDA or cuBLAS) to empirically prove that the Tensor Core throughput limiter is deactivated.
- **Real-Time Throughput Measurement**: Measures instantaneous TFLOPS achieved on the installed card.
- **Hardware Rate Limiter Assessment**:
  - **GA102 (RTX 3090 / 3090 Ti)**: Stock throttled baseline is ~40–65 TFLOPS; unlocked rate achieves ~110–130 TFLOPS (~1.9x to 2.16x throughput uplift).
  - **GA104 (RTX 3070 Ti)**: Stock throttled baseline is ~40–44 TFLOPS; unlocked rate achieves ~85–90 TFLOPS.
- **1-Click Silicon Test**: Click **Run Live Silicon Tensor Check** in the UI to perform a 50-iteration benchmark pass in seconds.

#### 3. Live NVIDIA Telemetry
- Direct integration with `nvidia-smi` to display live GPU name, driver version, core temperature, VRAM utilization, power draw (Watts), SM clock speed, and memory clock speed.
- Click **Refresh Telemetry** to refresh both verification checks and live GPU statistics simultaneously.

---

### Tab 7: Emergency Recovery
Provides a 1-click failsafe mechanism to revert any bootloader adjustments:

- **Restore Windows Boot Manager (1-Click)**:
  - Invokes `bcdedit` and UEFI NVRAM commands to place Windows Boot Manager (`{bootmgr}`) at priority position #1 in `{fwbootmgr}` displayorder.
  - Removes any experimental or secondary unlock boot entries.
- **Black Screen Troubleshooting**:
  - Provides quick instructions on monitor cable reconnection, display timeout intervals (30 seconds for Windows driver initialization), and cold power-cycle recovery.

---

## 5. Command-Line Interface (CLI) Reference

The utility supports full automation through the `-Cli` parameter. This is ideal for CI testing, scheduled diagnostics, or remote administration.

### CLI Syntax & Parameters

```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action <Action> [Parameters]
```

| Parameter | Type | Allowed Values / Description |
| :--- | :--- | :--- |
| `-Cli` | Switch | Enables headless command-line execution (suppresses WPF GUI). |
| `-Action` | String | `Audit`, `Preflight`, `CheckUsb`, `DeployUsb`, `StageProbe`, `BuildLocalUsb`, `RestoreWindows`, `Telemetry`, `VerifyTensor`, `CheckCaptures`, `CompareReports`, `GenerateDumps`, `DownloadAssets`. |
| `-DriveLetter` | String | Target drive letter for USB operations (e.g., `E` or `E:`). Removable USB FAT32 drives only; system and boot partitions are rejected. |
| `-CapturePath` | String | Folder containing `DIAGnn.TXT`, `IMGnn.BIN`, `PROM.BIN` for analysis. |
| `-DumpType` | String | For `GenerateDumps`: `Windows`, `EfiCaptures`, or `ProbeUsb`. |
| `-DumpPath` | String | Destination path for generated diagnostic dumps. |
| `-LeftReport` | String | Path to first JSON report for comparison. |
| `-RightReport` | String | Path to second JSON report for comparison. |
| `-ExportPath` | String | Destination file path to save compatibility JSON output. |
| `-Lang` | String | Language for reports and descriptions: `en` (default) or `ko`. |
| `-Json` | Switch | Emits pure JSON string to stdout (ideal for script piping). |
| `-OptIn` | Switch | Explicit opt-in required when staging diagnostic probe to a removable USB drive. |

---

### CLI Action Examples

#### 1. Hardware & GPU Compatibility Audit
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action Audit
```
*Outputs JSON with Motherboard, BIOS, CPU, OS, and GPU PCI identifiers.*

#### 2. Run Safety Pre-Flight Verification
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action Preflight
```
*Evaluates Secure Boot, Fast Startup, BitLocker, and firmware asset integrity.*

#### 3. Inspect Connected USB Storage Devices
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action CheckUsb
```
*Lists all removable disks, filesystems, and capacity.*

#### 4. Stage Unlock Payload to USB Drive
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action DeployUsb -DriveLetter E
```
*Stages `BOOTX64.EFI` and firmware assets onto FAT32 drive `E:`.*

#### 5. Offline Compatibility Check on Pre-boot Captures
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action CheckCaptures -CapturePath "D:\RTX3090-UNLOCK"
```

#### 6. Export Pure JSON Compatibility Report
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action CheckCaptures -CapturePath "D:\RTX3090-UNLOCK" -Json -ExportPath ".\my_report.json"
```

#### 7. Compare Two Compatibility Reports
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action CompareReports -LeftReport ".\baseline.json" -RightReport ".\probe.json"
```

#### 8. Generate Windows Diagnostic State Dump
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action GenerateDumps -DumpType Windows -DumpPath ".\diagnostics"
```

#### 9. Prepare a Diagnostic Capture Probe USB Drive
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action StageProbe -DriveLetter E -OptIn
```
*Compiles the read-only Diagnostic Probe targeting the system Windows ESP GUID and stages it to removable FAT32 USB drive `E:`. Explicit `-OptIn` is required, non-USB targets and system/boot partitions are rejected, and existing destination files are refused without overwrite.*

#### 10. Query Real-Time GPU Telemetry & Dual Verification Status
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action Telemetry
```
*Outputs Check 1 (Hardware Register Verification via UEFI NVRAM / boot report), Check 2 (Silicon Functional Verification via live Tensor Core GEMM test), and live `nvidia-smi` hardware metrics.*

#### 11. Run Live Silicon Tensor Core Functional Verification
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action VerifyTensor
```
*Runs an immediate 4096 x 4096 FP16 GEMM benchmark directly on GPU silicon, measures real-time TFLOPS, calculates uplift ratio vs. locked baseline, and verifies that the hardware rate limiter is lifted.*

#### 12. 1-Click Restore Windows Boot Manager
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action RestoreWindows
```

#### 13. Automated 1-Click Firmware Assets Download & Verification
```powershell
.\tools\gpu_unlock_utility\GpuUnlockUtility.ps1 -Cli -Action DownloadAssets
```
*Downloads the official pinned NVIDIA open kernel module source and nvidia-utils package, synthesizes the V67 image, extracts all 5 required GA102 firmware assets, and verifies SHA-256 hashes against `unlock\assets.json`.*

---

## 6. Diagnostic Dumps & Hardware Captures

The utility offers built-in diagnostic routines to facilitate troubleshooting and community validation:

### 1. Windows Diagnostic Bundle (`-DumpType Windows`)
Gathers comprehensive system information and saves it into `diagnostics\GPU-UNLOCK-DIAG-<timestamp>\`:
- `WINDOWS-INVENTORY.JSON`: Complete WMI and PCI hierarchy data.
- `NVIDIA-SMI-DUMP.XML`: Clock limits, power draw, temperature, VBIOS versions, and BAR addresses.
- `SYSTEM-SUMMARY.JSON`: Secure Boot, BitLocker, BIOS, and OS build information.
- `DISPLAY-EDID.JSON`: Active display connection records and EDID hex blocks.
- `README.TXT`: Diagnostic bundle manifest.

### 2. UEFI Capture Generator (`-DumpType EfiCaptures`)
Uses `generate_captures.py` to create **synthetic software-test fixtures**, not observations from the detected GPU. The GUI uses a new, uniquely named folder under `synthetic-captures/`, never the selected hardware-capture folder. Existing destinations are refused. The generated logs, README and metadata identify the files as synthetic; no hardware was observed. They are not cold-boot, compatibility or unlock evidence and must not be used to qualify an unlock build or hardware run.

### 3. USB Diagnostic Probe (`-DumpType ProbeUsb`)
Sets up a removable FAT32 USB drive to capture live pre-boot hardware state on cold boot without applying unlock modifications.

### Understanding Probe Artifacts in `RTX3090-UNLOCK\`:
When booting the diagnostic probe USB, several files are created in the `RTX3090-UNLOCK\` folder:
- **`PROM.BIN` (1,048,576 bytes / 1 MB)**: A raw dump of the physical GPU VBIOS ROM read directly from the PCI expansion ROM BAR.
- **`IMG00.BIN` through `IMG35.BIN` (~36 files)**: Raw dumps of each UEFI driver loaded into motherboard memory during pre-boot (PCI bus driver, console handles, and the NVIDIA GOP display driver `nvgop.efi`).
- **`DIAG00.TXT` / `DIAG01.TXT`**: Text logs detailing PCI configuration registers, strap states, and handle ownership graphs across consecutive cold boots.
> *Note: Having ~35 `.BIN` files created during probe runs is completely normal and required for machine profile generation.*

---

## 7. Companion Helper Scripts

The `tools\gpu_unlock_utility\` directory includes dedicated helper scripts:

### download_assets.py (Automated Firmware Asset Acquisition)
Downloads the pinned official NVIDIA open kernel module source archive (`610.43.03`) and `nvidia-utils` package, synthesizes the V67 signature payload, extracts Falcon microcontroller and GSP boot assets, and verifies all 5 files against `unlock\assets.json`:

Cache cleanup removes only the two known source archives created during the current run. Existing archives and unrelated files are retained. An existing cache file with the wrong hash is refused; choose a new cache directory instead of overwriting it. Downloads use unique temporary files and refuse an occupied final destination. Extraction uses a private temporary child directory; the caller's cache directory and any existing `temp_extract` folder are never recursively deleted. `--keep-cache` also retains newly downloaded archives. Download, source and final asset hash checks are unchanged.

```powershell
python .\tools\gpu_unlock_utility\download_assets.py
```

### Check-Assets.ps1 (Firmware Integrity, Download & Import)
Validates files in `assets\` against the project's SHA-256 specification in `unlock\assets.json`. Can also automatically trigger the download pipeline or scan external folders:

```powershell
# Verify current assets
.\tools\gpu_unlock_utility\Check-Assets.ps1

# Automatically download, extract, and copy all 5 firmware assets into assets/
.\tools\gpu_unlock_utility\Check-Assets.ps1 -Download

# Scan an external folder (e.g. Downloads) and automatically import matching assets
.\tools\gpu_unlock_utility\Check-Assets.ps1 -ImportFrom "C:\Users\<User>\Downloads\Firmware"
```

### generate_captures.py (Synthetic EFI Captures)
Generates labeled mock capture sets for software tests. Choose a **new** output directory; existing folders and capture files are never overwritten. `--count` accepts 1–32 synthetic records, not separate cold boots:

```powershell
# Generate test captures for an RTX 3090 (Device ID 220410de)
python .\tools\gpu_unlock_utility\generate_captures.py .\test_captures --device-id 220410de --count 2

# Generate test captures with EDID driver image included
python .\tools\gpu_unlock_utility\generate_captures.py .\test_captures --device-id 248210de --with-edid
```

---

## 8. Recommended End-to-End Walkthrough

Follow this standard procedure to unlock and verify your GPU:

```
[Step 1: Audit & Safety] ──> [Step 2: USB Staging] ──> [Step 3: Cold Boot] ──> [Step 4: Verify]
  - Run tools\Launch-Utility   - Format USB to FAT32      - Shut down PC           - Check Telemetry
  - Disable Fast Startup       - Stage files via Tab 3    - F8/F12 Boot Menu       - Run cuBLAS GEMM
  - Verify BitLocker status                               - Hand off to Windows    - Enjoy ~2x speedup
```

1. **Safety Pre-Flight**:
   - Launch `tools\Launch-Utility.cmd` as Administrator (or right-click `Launch-Utility.cmd` in `tools\` and select Run as Administrator).
   - In **Tab 2 (Pre-Flight Safety)**, verify that Secure Boot is disabled.
   - If Windows Fast Startup is enabled, click **Disable Fast Startup**.
2. **Stage USB Drive (Intelligent Route Selection)**:
   - Insert a FAT32 USB drive.
   - Navigate to **Tab 3 (USB Unlock Deployer)**.
   - For non-reference systems (e.g. Intel B460 + ASUS RTX 3090, or any setup where monitors are plugged directly into the RTX GPU), the utility detects the **Headless Single-RTX / Local Profile Route**.
   - **Step 1 (Diagnostic Probe)**: Click **1. Stage Diagnostic Probe** (or click Deploy). The utility automatically compiles a read-only probe embedded with your Windows ESP partition GUID.
3. **Record Pre-Boot Hardware Captures**:
   - Perform a **full system shutdown** (Power Off; do not use restart).
   - Turn on the PC and immediately press your motherboard one-time boot key (<kbd>F8</kbd> for ASUS, <kbd>F12</kbd> for Gigabyte, <kbd>F11</kbd> for MSI/ASRock).
   - Select `UEFI: <Your USB Drive>`.
   - The probe safely records your card's pre-boot registers (`DIAG00.TXT`, `IMG00.BIN`, `PROM.BIN`), and **immediately chain-loads Windows Boot Manager directly** (no BIOS loop).
   - Repeat once more (Full Cold Shutdown -> Boot USB) so 2 agreeing captures are recorded.
4. **Build & Stage Custom Unlock**:
   - Reopen the utility in Windows and navigate to **Tab 3**.
   - The capture counter will now show `2 of 2 complete [READY FOR CUSTOM UNLOCK BUILD]`.
   - Click **2. Build & Stage Custom Unlock Bootloader**. The utility compiles your machine's custom profile, runs host verification tests, and stages the custom headless unlock bootloader and assets onto the USB.
5. **Boot Staged Unlock & Verify**:
   - Shut down PC, boot the USB once from BIOS Boot Menu (<kbd>F8</kbd>).
   - The custom bootloader unbinds GOP, applies tensor selector registers (`SS0`/`SS1`), and immediately hands off to Windows.
   - Once Windows loads, open **Tab 6 (Verification & Telemetry)** and run cuBLAS benchmark to confirm the ~1.9x to 2.0x tensor throughput improvement!

---

## 9. Troubleshooting & FAQ

### Q: Why does the utility say "Administrator privileges are recommended"?
Certain operations—such as reading BitLocker volume status, disabling Fast Startup in the registry, and updating UEFI NVRAM boot priorities via `bcdedit`—require elevated Windows permissions. Launch via `tools\Launch-Utility.cmd` and select Option 1.

### Q: My USB drive does not appear in the dropdown.
The drive must be formatted with the **FAT32** filesystem to be recognized by UEFI firmware. Reformat the drive as FAT32 using Windows File Explorer or `diskpart`, then click **Refresh Disks**.

### Q: The screen remains black after booting from the USB drive.
- The unlock bootloader unbinds the pre-boot UEFI GOP driver to prepare hardware registers. The display will remain dark until the Windows graphics driver takes over.
- **Wait 30 to 45 seconds** after boot for Windows to reach the lock screen.
- Ensure your primary monitor is connected to a native **DisplayPort** connector on the GPU (DisplayPort 1.4 has the highest recovery and handoff success rate).

### Q: Is LLVM / Clang required to build the bootloader?
- **For staging and running the Diagnostic Probe**: **No**, the probe is pre-compiled in `release\EFI\BOOT\BOOTX64.EFI`.
- **For building a Custom Machine Unlock Bootloader (`new-machine.ps1` / Tab 3 Option 2)**: **Yes**. LLVM (`clang.exe` and `lld-link.exe`) is required because it compiles freestanding UEFI PE/COFF binaries (`/subsystem:efi_application`) and runs the offline 22-suite mock verification harness. Install via `winget install LLVM.LLVM`.

### Q: The screen stopped updating at `pre-release-cold-ss0 status=0x...` when booting the unlock USB. Is it stuck?
**No, this is completely normal for single-GPU systems.** Because the system has no integrated GPU and a single discrete RTX card, the bootloader explicitly prints:
> *"SINGLE RTX HEADLESS UNLOCK RESEARCH: one guarded attempt, then Windows. Screen may stop updating."*

At `pre-release-cold-ss0`, the bootloader safely detaches the UEFI GOP display console so the GPU's display controller can be reset and unlocked without crashing the motherboard firmware. The display output is designed to freeze on that last frame while the unlock transaction completes in memory and immediately chain-loads `bootmgfw.efi` (Windows).

### Q: Why are there ~36 `.BIN` files (`IMG00.BIN`–`IMG35.BIN`) created in `RTX3090-UNLOCK`?
When the diagnostic probe runs, it queries every loaded EFI image in UEFI RAM and saves exact binary dumps of the motherboard's pre-boot environment (including `nvgop.efi`, the PCI bus driver, and `PROM.BIN`). The profile generator requires these files to verify driver compatibility and calculate exact VBIOS checksums. Having ~35 `.BIN` files is normal and expected.

### Q: How do I completely undo the unlock?
- If using the **USB route**: Simply unplug the USB drive or boot normally from your internal drive. No permanent changes were written to your GPU.
- If using the **Internal ESP route**: Open the utility, switch to **Tab 7 (Emergency Recovery)**, and click **Restore Windows Boot Manager (1-Click)**.

### Q: PowerShell reports "Execution of scripts is disabled on this system".
Run the following command in PowerShell to allow script execution for the current session:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
Alternatively, launch through `tools\Launch-Utility.cmd`, which handles execution policy bypass automatically.
