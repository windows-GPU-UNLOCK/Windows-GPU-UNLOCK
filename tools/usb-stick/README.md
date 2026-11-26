# GPU-UNLOCK USB stick: full guide

**English** | [Русский](README.ru.md)

*Vibecoded with love by Claude.*

`make-stick.ps1` turns a FAT32 USB stick into a GPU-UNLOCK boot stick **for your own PC** in
two runs of one command. It drives the project's
[local-profile pipeline](../../docs/NEW-MACHINE.en.md) and puts a small boot menu in front:

```
 GPU-UNLOCK boot menu
 Profile: LOCAL-220410de-145410de-dda39bf5

  1. Windows + GPU-Unlock
  2. GPU dump (read-only probe), then Windows without unlock
  3. Windows without GPU-Unlock

 Up/Down + Enter, or press 1, 2, 3.  Esc = 3.
 Item 1 starts in 20 s. Any key stops the timer.
```

Keep the stick first in the BIOS boot order and every power-on goes through this menu. Item 3,
or simply removing the stick, boots Windows exactly as before. Nothing is installed on your
internal disk, and the unlock only lives in the GPU until the next power-off.

What it is not: it does not add hardware support, widen `research/profile/proven.json`,
or skip any project check. The profile gates, the 22 host jobs, the evidence binding and every
runtime check in the wrapper and child run unchanged. If your PC is outside the proven envelope,
the script stops exactly where the project stops. A stick built on one PC does not work on
another: the checks refuse it and Windows just boots without the unlock.

## Contents

1. [Will it work on my PC?](#1-will-it-work-on-my-pc)
2. [Prepare Windows](#2-prepare-windows)
3. [Prepare the BIOS](#3-prepare-the-bios)
4. [Build the stick](#4-build-the-stick)
5. [First unlock and checking it](#5-first-unlock-and-checking-it)
6. [Daily use](#6-daily-use)
7. [When something changes](#7-when-something-changes)
8. [Troubleshooting](#8-troubleshooting)
9. [Undo everything](#9-undo-everything)
10. [Reference](#10-reference)

## 1. Will it work on my PC?

You need **all** of these:

- One NVIDIA card from the [proven envelope](../../docs/NEW-MACHINE.en.md#what-it-accepts): RTX 3090 / 3090 Ti,
  RTX 3080 12GB (`220a`), RTX 3070 8GB (`2484`), RTX 3060 Ti 8GB (`24c9`), RTX 3060 12GB (`2487` / `2504`).
  Exact chip, VRAM and firmware-driver versions are checked later from the dumps. The board
  brand does not matter. Only one NVIDIA GPU may be installed.
- A UEFI motherboard with **AMI** firmware (most ASUS, MSI, Gigabyte and ASRock boards), CSM off.
- Monitors connected to the RTX. The RTX must own the only firmware display, so an iGPU must
  be disabled or must not drive a screen at boot.
- Windows 10/11 x64 installed in UEFI mode.

No dump yet? `python -I .\tools\collect_compatibility.py` prints a harmless inventory
([START-HERE](../../docs/START-HERE.en.md)). The real verdict comes from the two dumps in step 4.

## 2. Prepare Windows

1. **Get the repository**: *Code → Download ZIP* and extract it to a short path such as
   `C:\GPU-UNLOCK\`, or `git clone`. Do not run anything from inside the ZIP preview.
2. **Python 3.14 or newer** from [python.org](https://www.python.org/downloads/windows/) with the
   *py launcher*. Check: `py -3.14 --version`.
3. **Visual Studio 2022 Build Tools** (or Visual Studio 2022) with the workload
   **Desktop development with C++** (MSVC v143 + Windows 11 SDK). These are needed for the host tests.
   LLVM 20.1.8 is downloaded by the script itself (896 MiB, SHA-256 pinned).
4. **Turn off Fast Startup.** Otherwise "Shut down" is not a real power-off:
   *Control Panel → Power Options → Choose what the power buttons do → uncheck Turn on fast startup*,
   or in an administrator PowerShell:
   ```powershell
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 0 /f
   ```
5. **BitLocker / device encryption.** Check *Settings → Privacy & security → Device encryption*
   (or `manage-bde -status C:` as administrator). If C: is protected, turning off Secure Boot will ask for
   the recovery key. Have it ready (https://aka.ms/myrecoverykey) or turn encryption off first.
6. **A USB stick formatted FAT32** (any size; 8–32 GB is easiest).
   - Up to 32 GB: *Explorer → right-click → Format → FAT32*.
   - Larger sticks: Windows only offers exFAT/NTFS. Use a tool that formats large FAT32 (for
     example Rufus: *Non bootable*, *Large FAT32*), or create a ≤32 GB partition with `diskpart`.
     Double-check you picked the stick: formatting erases it.
   - The script never formats or partitions anything itself.
7. About **2 GB free** in `%LOCALAPPDATA%\GPU-UNLOCK` (LLVM, downloads, generated firmware).

## 3. Prepare the BIOS

Enter setup (usually **Del**; ASRock **F2**) and set:

| Setting | Value | Where it usually is |
|---|---|---|
| Secure Boot | **Disabled** | MSI: Settings → Advanced → Windows OS Configuration → Secure Boot · ASUS: Boot → Secure Boot → OS Type = *Other OS* · Gigabyte: Boot → Secure Boot · ASRock: Security → Secure Boot |
| CSM / Legacy | **Disabled** (UEFI only) | Boot section (MSI: *Windows OS Configuration → BIOS UEFI/CSM Mode = UEFI*) |
| Primary display | **PCIe / PEG**; iGPU disabled if it would drive a screen | Intel: *Initiate Graphic Adapter = PEG*, *IGD Multi-Monitor = Disabled* · AMD: *Integrated Graphics = Disabled* |
| Boot order | the stick **first** (after it is built), Windows Boot Manager second | Boot → Boot Option #1 |

Names differ per board and BIOS version, so check your manual.

You can always pick the stick or Windows once from the **boot-menu key**:

| Vendor | Boot menu | Setup |
|---|---|---|
| MSI | F11 | Del |
| ASUS | F8 | Del / F2 |
| Gigabyte | F12 | Del |
| ASRock | F11 | F2 / Del |

Choose the entry that starts with **UEFI:** for the stick.

> The first boot right after *Save & Exit* is a warm reset, not a power-on. Never take a dump on
> that boot: shut down once more first.

## 4. Build the stick

Open a normal (not administrator) **Windows PowerShell** in the repository root. `E` below is
your stick's drive letter. Use the same command for both runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\usb-stick\make-stick.ps1 -Drive E -StageUnlock
```

Want to see first what it would do? Add `-Check`: it changes nothing.

**Run 1 (about 10–20 minutes, mostly downloads):**
- checks the stick, Python, Fast Startup, Secure Boot, BitLocker and MSVC;
- downloads and extracts clang/lld-link 20.1.8;
- generates the five NVIDIA firmware files on Windows, without WSL;
- builds the project's read-only probe and puts it on the stick behind the **dump-phase menu**.
  In that menu, item 1 is shown as *not ready* and the screen counts the dumps on the stick.

**Then take two dumps:**
1. *Start → Shut down* (not Restart). Wait until the PC is completely off.
2. Power on and boot the stick (first in the boot order, or via the boot-menu key).
3. In the menu press **2**. The probe reads the GPU (read-only), saves `DIAGnn.TXT`, `PROM.BIN` and
   `IMGnn.BIN` to the stick, and starts Windows.
4. Repeat once more. You need **2** dumps from **separate full shutdowns**.

**Run 2 (same command; a few minutes):**
- checks the dumps (`check-compatibility.py`). If they disagree, it shows which value or PCI
  register differs and what to do;
- runs `research/profile/new-machine.ps1`: profile → **22 host jobs** → USB package → project staging
  (unlock wrapper, child, firmware files);
- replaces the dump-phase menu with the normal menu. The stick is ready.

Without `-StageUnlock`, run 2 stops after the package and nothing that writes to the GPU goes on
the stick. Add the flag when you are ready.

## 5. First unlock and checking it

Be at the PC for the first one.

1. Shut down, power on, boot the stick. Let item 1 start, or press 1, and then **press nothing**.
2. The project's wrapper waits 5 s (Esc there means Windows without unlock), checks that the GPU is in
   its power-on state, then the screen goes black for a moment. One guarded transaction runs, and
   Windows starts directly.
3. **If it stays black for more than 2–3 minutes:** remove the stick, hold the power button until
   the PC is off, and power on. Windows boots normally; the GPU firmware is never flashed.

Check the result:

- `RTX3090-UNLOCK\AUTO000000\REPORT.TXT` on the stick should end with
  `FINAL status=0 stage=transaction attempted=1 driver_release=0 clean=1`.
- Measure with the [project benchmark](../../docs/BENCHMARK.en.md): `benchmark\setup.ps1`, `build.ps1`,
  `run-benchmark.ps1`, before (item 3) and after (item 1) on the same driver.
  - The benchmark targets CUDA 12.6 with MSVC 14.29. On VS 2022, add the *MSVC v142* component and
    pass a `vcvars` wrapper that calls `vcvars64.bat -vcvars_ver=14.29`, or build with
    `-AllowUnsupportedCompiler`.
  - Close GPU-heavy apps first: the runner refuses to start above 5% GPU load.
- On the reference machine (RTX 3090, MSI Z390) FP16 went 70 → 124 TFLOPS, BF16 70 → 129 and
  TF32 36 → 65; FP32 was unchanged. Games and most apps do not change. Only FP16/BF16/TF32 tensor
  math (AI training and inference) does.

## 6. Daily use

- **Shut down → power on** gives a cold GPU, and item 1 unlocks it.
- **Restart:** some boards reset the GPU on restart (the unlock runs again), others do not. In
  that case the wrapper sees a GPU that is not cold and simply boots Windows without unlock. Use
  shut down + power on when you need it.
- **Sleep / hibernate** loses the unlock. Disable sleep if you rely on it.
- **Fast Startup must stay off.**
- Changing the NVIDIA Windows driver is outside the pre-boot part. Reports so far used
  610.88–621.01. If something misbehaves, use item 3.
- Keep the stick private: `RTX3090-UNLOCK\ASSETS\` holds NVIDIA firmware for your personal use only.

## 7. When something changes

| Change | What to do |
|---|---|
| BIOS update or BIOS settings that affect PCIe/display, another GPU, another PCIe slot, Windows reinstall (new ESP) | `make-stick.ps1 -Drive E -StageUnlock -ArchiveCaptures`, then two new dumps (item 2), then the same command without `-ArchiveCaptures` |
| New version of this repository | the same command (it regenerates, re-tests and re-stages; if it then complains about the dumps, add `-ArchiveCaptures` and take two new ones) |
| Only the menu (timeout, default item) | `make-stick.ps1 -Drive E -MenuOnly -MenuTimeout 10 -MenuDefault 3` |

## 8. Troubleshooting

| Symptom | Meaning / fix |
|---|---|
| The stick does not appear in the boot menu, or the PC skips it | Secure Boot still on, CSM on, or the stick is not FAT32. Pick the **UEFI:** entry. |
| `Fast Startup must be off` | Step 2.4. |
| `Dumps are not usable yet: captures_disagree` | It prints the differing value. PCIe *Link Status* registers mean one dump came from a warm reset. Run with `-ArchiveCaptures` and take two new dumps after full shutdowns. Never edit dumps. |
| `cold_state` / *not in its power-on state* | A dump was taken after Restart. Archive and redo it after a full shutdown. |
| `outside_scope`, `gpu_scope`, `driver_scope`, `topology_scope` | This PC is outside the proven envelope. Stop here; consider a [compatibility report](../../docs/CONTRIBUTING.en.md). Do not force it. |
| `attributes_mismatch` | Known PCI attribute-cache case ([#102](https://github.com/impacifist/Windows-GPU-UNLOCK/issues/102)); not supported by the automatic route. |
| Menu says *the selected item returned* | The wrapper or probe stopped before touching the GPU (for example a hash mismatch after a rebuild: run `-MenuOnly`). The menu then boots Windows. |
| Black screen after item 1 | See 5.3. Then send `REPORT.TXT` and `HLS*.TXT` (remove device paths) in an issue. |
| Host test failure in run 2 | Do not stage. Keep the output and open an issue. |

## 9. Undo everything

1. BIOS: put **Windows Boot Manager** first (or remove the stick) and turn **Secure Boot** back on.
2. Optionally turn Fast Startup back on.
3. Delete `%LOCALAPPDATA%\GPU-UNLOCK` and the repository folder; wipe the stick.

Nothing else was changed on the PC.

## 10. Reference

### Options

| Option | Meaning |
|---|---|
| `-Drive E` | the FAT32 USB stick (required) |
| `-StageUnlock` | in run 2, also write the unlock and the normal menu (otherwise stop after the package) |
| `-Check` | report the state and the next step; write nothing |
| `-MenuTimeout 1..99` | seconds before the default item starts (20) |
| `-MenuDefault 1/2/3` | default item of the normal menu (1). The dump-phase menu always defaults to 3. |
| `-MenuOnly` | rebuild and restage only the menu |
| `-ArchiveCaptures` | move old dumps to `RTX3090-UNLOCK\old-*` (copy in `%LOCALAPPDATA%\GPU-UNLOCK\captures-archive`) |
| `-WorkDir`, `-Clang`, `-LldLink`, `-Python`, `-VcVars` | use your own paths/tools |

Do not pipe the output (`*>&1`, `Tee-Object`) in Windows PowerShell 5.1. The Python tests write
to stderr, and the redirection turns that into a terminating error inside the project's scripts.

### Files

| File | Role |
|---|---|
| `make-stick.ps1` | the two-run driver |
| `prereqs.py` | `llvm` (pinned LLVM), `firmware` (assets without WSL), `diff` (explain disagreeing dumps) |
| `menu.c` | the boot menu (UEFI application, about 11 KiB) |
| `build-menu.ps1` / `stage-menu.ps1` | build and place the menu (normal or `-ProbeOnly` dump phase) |

### Firmware assets without WSL

`prereqs.py firmware` downloads the upstream generator files from
`Zagitta/gpu-unlock@0ebdb1c` (SHA-256 pinned) and the NVIDIA 610.43.03 open kernel sources.
It imports the generator unchanged and checks the five outputs against
`internal-boot/unlock/assets.json`. Python 3.14 reads `.tar.zst` natively, so no `zstd.exe` is needed.

The CachyOS URL pinned upstream for nvidia-utils 610.43.03-1 currently serves an HTML page instead
of the package. The script then uses the official Arch build of the same release
(`archive.archlinux.org`, SHA-256 pinned). Only the whole-package hash differs: `.PKGINFO`,
`gsp_ga10x.bin`, the NVIDIA license and every generated file are still checked against the upstream pins.

### Stick layout

| Path | Content |
|---|---|
| `EFI\BOOT\BOOTX64.EFI` | the menu |
| `EFI\GPU-UNLOCK\UNLOCK.EFI` | the project's headless USB wrapper (byte-identical to `build-usb.ps1` output) |
| `EFI\GPU-UNLOCK\PROBE.EFI` | the project's generic read-only probe |
| `EFI\WindowsGPUUnlock\UNLOCK-HEADLESS.EFI` | the child, where the wrapper expects it |
| `RTX3090-UNLOCK\ASSETS\` | firmware assets: personal use only |
| `RTX3090-UNLOCK\` | logs (`HLS*.TXT`, `AUTO*\REPORT.TXT`), dumps (`DIAG*`, `PROM.BIN`, `IMG*`), `backup\` |

### How the menu chain-loads safely

- It reads `UNLOCK.EFI` / `PROBE.EFI` into memory, checks the size and SHA-256 compiled in from
  `usb-manifest.json` / the probe manifest, and starts **those bytes** with `LoadImage(SourceBuffer)`
  and a device path on the same USB volume. This is the pattern the wrapper itself uses for its child.
  The images' `DeviceHandle` is therefore the stick, and their USB-only `Prepare()`, child hash
  check and pinned Windows ESP handoff run unchanged.
- It prints text, reads keys and lists `\RTX3090-UNLOCK` (to count dumps). It never touches the GPU,
  changes no text or GOP mode, and installs no driver binding, so the release-path driver-image
  checks do not see it.
- It drains the key buffer before starting the wrapper, so the key that chose item 1 cannot
  reach the wrapper's Esc window.
- If item 1 or 2 returns, nothing was released, because the wrapper halts instead of returning after
  release. The menu then boots Windows from the pinned ESP. If that fails too, it returns to the
  firmware boot order.
- It disables the firmware's 5-minute boot watchdog so the menu can stay open; the wrapper and
  probe disable it themselves anyway.
- The dump phase pins only the probe and refuses item 1. Dumps taken with a different probe build are
  moved to `old-*`, the same rule `new-machine.ps1` applies.
- `tools/` is outside `Get-LocalTreeInputs`, so this folder does not change the LOCAL evidence digest.

### Hardware record

MSI MPG Z390 GAMING EDGE AC / i9-9900K / Inno3D RTX 3090 iChill X4 ([compatibility report #528](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/528)), all cold boots:

- two supervised unlocks through the menu (`FINAL status=0 clean=1` both times, Windows returned);
- one menu item-2 dump that agrees with the profile captures on every compared value.

Repository benchmark, locked → unlocked: FP16 70.0 → 124.2 / 123.4, BF16 69.9 → 129.0 / 128.9,
TF32 36.1 → 65.4 / 64.9 TFLOPS. This is one machine, not a support claim. Please report yours ([CONTRIBUTING](../../docs/CONTRIBUTING.en.md)): the
`profile.json` values, `REPORT.TXT` and the benchmark, never `PROM.BIN`, `IMG*.BIN` or the assets.
