# Issue 109: attended B560M graph capture

**English** | [한국어](B560M-GRAPH-TEST.ko.md)

This preparation is pinned to Gigabyte B560M DS3H V2 BIOS `F7 RB`, i5-11400F,
and one RTX 3060 `2487 / 1458:4072`. It does not reuse another board's unlock
profile. It prepares the same limited graph diagnostic as #33: protocol/open
relationships, console variables, GOP metadata and PCI headers, a USB log, then
an attempted Windows handoff. No GPU MMIO/PROM reads, driver image dumps,
driver release, GPU writes or firmware-variable writes. The existing handoff
disables the EFI watchdog. The graph guides later resource/driver qualification;
it does not establish unlock support.

Firmware/display/input or Windows handoff may hang. Recovery is unproven and
may require power-off, USB removal and normal Windows Boot Manager selection.
No automatic reboot, retry or rollback. Read the boundary and accept it before
staging; participation is optional. Do not change Secure Boot or other settings.

Use an existing FAT32 USB with 16 MB free, Python and LLVM. Secure Boot must
already be off. Open administrator PowerShell in the extracted pinned source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue109
```

Enter the USB letter and type `PREPARE` only if you accept the explained risk.
The script verifies the Windows-reported exact machine/single GPU, current
Windows ESP and USB, backs up/verifies the old USB boot loader and checks the
new copy. It never formats a disk. Stop on any mismatch, error or organizational
policy block; report the short message with personal paths removed. Do not
change settings or bypass guards.

After **READY**, fully shut down and manually select that USB once from the
firmware boot menu. No test hotkeys. Expected: graph capture then direct Windows
boot. If Windows has not started within two minutes, power off, remove the USB
and use normal Windows Boot Manager. If recovery fails, stop. Do not repeat.

In Windows, reconnect the USB if needed and collect using the same script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue109 -Collect
```

Attach reviewed **graph-summary.json** from the printed Documents folder and
state whether Windows started directly or manual recovery was needed. Keep raw
DIAG/EFI/backups local. Remove USB after collection. The summary exports numeric
graph relationships and completion markers, excludes raw paths, and grants no
write eligibility. Firmware behavior and Windows recovery on this exact board
remain unverified until the attended run is assessed.
