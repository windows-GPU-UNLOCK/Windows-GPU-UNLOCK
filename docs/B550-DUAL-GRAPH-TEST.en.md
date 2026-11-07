# Issue 180: attended NVIDIA + AMD graph capture

**English** | [한국어](B550-DUAL-GRAPH-TEST.ko.md)

Exact preparation pins: Gigabyte B550 AORUS ELITE V2 BIOS F19, Ryzen 5 5600G,
NVIDIA `2489 / 10de:153c` and AMD `1638 / 1458:d000`. Both PCI display adapters
must remain present. Keep the two reported monitor cables where they are.
ROOT/SWD virtual adapters are not removed or treated as firmware GOP proof.

The graph diagnostic records firmware protocol/open relationships, console
variables, GOP metadata and PCI headers for the exposed adapters, writes a USB
log, then attempts Windows handoff. No GPU MMIO/PROM reads, image dumps,
driver release, GPU writes or unlock. The existing handoff disables the EFI
watchdog. This records the actual preboot graph; two Windows display adapters
do not prove that firmware exposes a usable independent AMD GOP.

Firmware/display/input or Windows handoff may hang; recovery is unproven and
may require power-off, USB removal and normal Windows Boot Manager. No automatic
reboot/retry/rollback. Accept this boundary before staging. Secure Boot must
already be off; do not change settings or monitor connections for this test.

With Python/LLVM installed and an existing FAT32 USB with 16 MB free, open
administrator PowerShell in the extracted pinned source and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue180
```

Enter USB letter and `PREPARE` only after reading and accepting the boundary.
The script checks the exact machine/both PCI adapters, current Windows ESP and
USB identity, preserves/verifies the previous USB boot loader, and verifies the
new copy. No formatting. On any mismatch, error or policy block, stop and report
the short message with personal paths removed; do not bypass a check.

After **READY**, fully shut down and manually boot that USB once. No hotkeys in
the test. Expect graph capture then Windows. If Windows has not started within
two minutes, power off, remove USB and use normal Windows Boot Manager. Stop if
recovery fails and do not repeat the run.

Back in Windows, reconnect USB if needed and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue180 -Collect
```

Attach reviewed **graph-summary.json** from the printed Documents folder and
state whether Windows started directly or manual recovery was required. Keep raw
DIAG/EFI/backups local and remove USB after collection. This is not an unlock or
hardware-support claim; it supplies topology evidence for the next profile step.
