# MSI Cyborg graph-only attended research (issue130 MSI contributor)

[한국어](MSI-CYBORG-GRAPH.ko.md)

This is separate from the HP Victus opening report. Exact preparation pins:
MSI MS-15K1, manufacturer Micro-Star International Co., Ltd., BIOS E15K1IMS.114,
i7-13620H, Intel8086:A7A8/1462:13B9 and NVIDIA10DE:28A1/1462:13B9.
The Windows monitor-parent result associates the active monitor with Intel;
it does not establish physical MUX routing or preboot ownership. Keep the internal
panel, MuMu virtual adapter, cables, MUX, firmware and power settings unchanged.
Unknown non-PCI identity formats remain refused; configuration cannot admit
MMIO, release or unlock. No laptop unlock route is qualified.

New optional boundary: firmware handle/protocol/open metadata, console variables,
GOP mode metadata and64-byte PCI headers for exposed adapters, USB log and
attempted Windows return. No GPU MMIO/PROM, image dumps, driver release, reset,
GPU writes, firmware uploads/execution or unlock. Firmware/display/input may
hang and Windows may not start. Existing handoff disables the EFI watchdog;
recovery on this laptop remains unproven. No automatic reboot/retry/rollback.
Only the device owner can accept one attended run before preparation.

In fresh pinned source, administrator PowerShell, with Python/LLVM already on
Windows and an existing FAT32 USB with16MB free:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue130-msi
```
Secure Boot must already be off and the system volume must be observed fully
decrypted. If either changed/is unknown, stop; do not change settings/encryption.
The script checks machine/current Windows ESP/USB, asks PREPARE for acceptance,
builds/verifies the actual Windows-pinned image, backs up and readback-checks the
old USB loader and staged copy. Live encryption/SecureBoot are rechecked before
staging. Unknown identity/tool/policy/error: stop, do not bypass or install.

After READY only, fully shut down and manually select the USB ONCE; no Shift.
Expect graph logging then Windows. If Windows has not started in2minutes, power
off, remove USB and use normal Windows Boot Manager. If recovery fails, stop.
Never repeat the run even after an incomplete capture/refusal. After Windows,
reconnect USB if needed and run the same command with -Collect. Return only
reviewed graph-summary.json from the printed Documents folder and direct/manual
Windows outcome. Raw logs/EFI/backups stay local; remove USB afterward.

Local configuration/refusal/staging/encryption tests passed and the shared
AMD64 EFI fixture built/PE-verified14848bytes,zeroimports,NX/dynamicbase.
Fixture SHA2563d476bb7498d28c8f4d6e5a041d8da4b60b4df212e9edc43c2465668cd28f6f6.
Never boot this synthetic-GUID fixture. No laptop EFI execution or recovery was
verified here. This observes topology toward research review, not unlock support.
