# Issue 31: attended X570 graph test

**English** | [한국어](X570-GRAPH-TEST.ko.md)

Exact preparation pins: ASUS PRIME X570-PRO BIOS 5013, Ryzen 9 5950X, sole PCI
display adapter `2204 / 10de:147d`. ROOT/SWD software adapters are not mistaken
for physical PCI GPUs or evidence of preboot ownership; unknown identities and
additional PCI display adapters are refused. Nothing is disabled or removed.

This is a diagnostic toward a profile: protocol/open relationships, console
variables, GOP metadata, PCI headers, USB log and attempted Windows handoff.
No GPU MMIO/PROM, driver image dumps, driver release, GPU writes or unlock.
The existing handoff disables the EFI watchdog. Firmware/display/input or Windows
boot may hang; recovery is unproven. No automatic boot, retry or rollback.

If you accept one attended run, use an existing FAT32 USB with 16 MB free,
Python and LLVM. Secure Boot must already be off; do not change settings for
this test. Open administrator PowerShell in the extracted pinned source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue31
```

Enter the USB letter, read the risk boundary and type `PREPARE` only if accepted.
The script checks the machine, Windows ESP and USB, preserves/verifies the old
USB boot loader and checks the new copy; it does not format or reboot. Stop on
any error, mismatch or policy block; report the short message with personal
paths removed rather than changing settings or bypassing a guard.

After **READY**, fully shut down and manually boot the USB once. No Shift keys.
Expect graph capture then Windows. If Windows has not started in two minutes,
power off, remove USB and use normal Windows Boot Manager. If recovery fails,
stop using the test. Do not repeat this run.

In Windows, reconnect the USB if needed and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue31 -Collect
```

Return reviewed **graph-summary.json** from the printed Documents folder and
whether Windows started directly or required manual recovery. Keep raw
DIAG/EFI/backups local; remove USB after collection. No EFI behavior or recovery
on this machine is claimed verified. This does not qualify an unlock profile.
