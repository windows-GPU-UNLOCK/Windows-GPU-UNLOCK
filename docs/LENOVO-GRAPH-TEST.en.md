# Issue 19: attended Lenovo graph capture

**English** | [한국어](LENOVO-GRAPH-TEST.ko.md)

Only for Lenovo 1052 BIOS S0AKT48A, i9-11900K, sole ASUS RTX 3060
`2504 / 1043:881d`. Keep the reported direct DisplayPort connection and disabled
iGPU as they are. The prior official ASUS VBIOS update remains part of the
machine history; this test does not read or change that firmware.

This is a graph diagnostic toward a profile: firmware protocol/open relationships,
console variables, GOP metadata, PCI headers, USB log and attempted Windows
handoff. No GPU MMIO/PROM reads, driver image dumps, driver release, GPU writes
or unlock. The existing handoff disables the EFI watchdog. Firmware/display/input
or Windows handoff may hang; recovery is unproven. There is no automatic boot,
retry or rollback. Accept this boundary before staging.

With Python/LLVM, an existing FAT32 USB with 16 MB free, and Secure Boot already
off, open administrator PowerShell in the extracted pinned source and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue19
```

Enter USB letter and `PREPARE` only after reading and accepting the boundary.
The script checks the exact machine/current Windows ESP/USB, preserves and
verifies the old USB boot loader, and verifies the new copy. No formatting.
Stop on error, mismatch or policy block; report the short message with personal
paths removed. Do not change settings or bypass checks.

After **READY**, fully shut down and manually boot that USB once. No Shift keys.
Expect graph capture then Windows. If Windows has not started within two minutes,
power off, remove USB and choose normal Windows Boot Manager. If recovery fails,
stop using the test. Do not repeat the run.

Back in Windows, reconnect USB if needed and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue19 -Collect
```

Return reviewed **graph-summary.json** from the printed Documents folder and
whether Windows started directly or required manual recovery. Keep raw
DIAG/EFI/backups local; remove USB afterward. The successful Windows collector
test does not establish this EFI's behavior or qualify an unlock profile.
