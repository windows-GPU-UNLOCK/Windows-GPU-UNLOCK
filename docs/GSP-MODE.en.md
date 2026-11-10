# NVIDIA GSP Mode Guide (Resolving Windows Code 43)

This guide documents the mechanism of NVIDIA GSP (GPU System Processor) Firmware Mode on Windows, why Code 43 or driver crashes occur after pre-OS unlocks, and how to resolve them using `tools/set-gsp.ps1`.

---

## 1. Background: CPU RM vs. GSP RM

On Windows, the standard NVIDIA kernel driver (`nvlddmkm.sys`) historically executes its **Resource Manager (CPU RM)** on the host processor.
- When an EFI pre-OS unlock mutates protected hardware registers (such as SEC2 / Falcon registers or memory apertures), the driver's CPU RM performs sanity checks during driver startup.
- If it detects unexpected register state, CPU RM halts initialization and reports **Error 43 (Code 43)** in Device Manager. Attempting to disable and re-enable the device can lead to a driver deadlock or Blue Screen of Death (BSOD).

Starting with driver release R510 (for Turing TU10x and Ampere GA10x architectures), NVIDIA introduced **GSP-RM Mode**.
- In GSP-RM mode,底层 resource management tasks are delegated to the on-die GSP Falcon processor (`GSP Firmware Version: 615.x+`).
- GSP mode operates natively with volatile memory protection zones (WPR2/FRTS) and avoids the rigid CPU-side register assertions, effectively eliminating driver Code 43.

---

## 2. Managing GSP Mode via `tools/set-gsp.ps1`

The `tools/set-gsp.ps1` script automates configuring the `EnableGpuFirmware` registry key across all detected NVIDIA display devices under `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}`.

### Usage (Run in Administrator PowerShell)

1. **Check current status**:
   ```powershell
   .\tools\set-gsp.ps1 -Status
   ```

2. **Enable GSP Mode (to fix Code 43)**:
   ```powershell
   .\tools\set-gsp.ps1
   ```
   *Action*: Sets `EnableGpuFirmware = 1` (DWORD) for all detected NVIDIA display adapters. Restart the system for changes to take effect.

3. **Revert to default driver mode (safe rollback)**:
   ```powershell
   .\tools\set-gsp.ps1 -Disable
   ```
   *Action*: Removes the `EnableGpuFirmware` value, restoring standard CPU-RM mode.

---

## 3. Quick Throughput Verification

After enabling GSP mode and booting through the unlock EFI, verify actual compute unthrottling using the zero-dependency benchmark:

```powershell
python .\benchmark\quick_gemm_bench.py
```
This runs a 4096 GEMM matrix multiplication directly through system cuBLAS in ~1.5 seconds, reporting median throughput (TFLOPS) without requiring CUDA SDK compilation.
