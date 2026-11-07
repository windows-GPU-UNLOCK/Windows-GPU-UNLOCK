# Shared graph diagnostic

[한국어](GENERIC-GRAPH-TEST.ko.md)

One preparation engine and one graph-only EFI build serve all configurations.
`research/profile/graph-configurations/*.json` contains data, not executable code:
board, manufacturer match rule, BIOS, CPU token and the complete expected PCI
display-adapter tuples. The ID is a test configuration, **not a supported unlock
profile**. Existing machine commands and the X99 entry point remain compatible.

Run from a fresh pinned source ZIP on Windows with Python and LLVM installed on
Windows, administrator PowerShell, and a FAT32 USB with at least 16 MB free:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue182
```

Use only the configuration named in your reviewed issue instructions. The script
checks actual inventory, Secure Boot already off, the current internal Windows
ESP and the USB identity. A mismatch or policy block means stop and report the
short error; do not edit JSON/guards, disable adapters, change firmware settings
or substitute another ID to make it pass. Unknown VBIOS history remains unknown;
this diagnostic neither reads it nor establishes qualification.

Before staging, read the displayed boundary and type `PREPARE` only if accepted.
Scope: firmware protocol/open records, console variables, GOP metadata and
64-byte PCI headers, USB diagnostic output, attempted Windows handoff. No GPU
MMIO/PROM, image dump, driver release, GPU writes or unlock. Existing Windows
handoff disables the EFI watchdog. Firmware/display/input can hang and Windows
return can fail; recovery is unproven. Existing USB loader is backed up and read
back; configuration hash is rechecked after build and recorded in graph-stage.json.
No formatting, boot-entry writes, automatic reboot, retry or rollback.

After READY, fully shut down and manually boot the USB **once**. No Shift keys.
Expect capture then Windows. If Windows has not started within two minutes,
power off, remove the USB and use normal Windows Boot Manager. If recovery fails,
stop using the test. Do not repeat. After Windows returns, reconnect USB if
needed and run the same command with `-Collect`. Return only the reviewed
`graph-summary.json` from the printed Documents folder, plus whether Windows
started directly or required manual recovery. Keep raw logs/EFI/backups local
and remove USB afterward. One result is reviewed before another test is proposed.

## Maintainer checks

`test-graph-configurations.ps1` tests every data file, refusal cases and the legacy
entry point. `test-x99-graph-preparation.ps1` tests existing pins and staging with
mock files only. `build-graph-only.ps1 -Fixture` verifies the common EFI; **never
boot a fixture** (empty Windows ESP GUID). Adding configuration data does not
add a GPU family or permit MMIO/release/unlock; those need separately reviewed
source, evidence and informed acceptance.

Configuration `issue184` pins MSI MAG X870E TOMAHAWK WIFI (MS-7E59), BIOS2.A91, Ryzen9800X3D, NVIDIA2204/1462:3882 and AMD13c0/1462:7e59. Keep all reported connections: three monitors and VR headset on NVIDIA, one monitor on AMD. Both adapters remain enabled. The VR connection does not establish firmware ownership, and no adapter may be silently discarded to pass validation. VBIOS history is unknown. Use the same reviewed graph-only command with `-Machine issue184`; all acceptance, stop/recovery and collection instructions above apply.

Graph export v2 retains fixed diagnostic failure labels and numeric status codes, including duplicate/conflicting observations. Unknown/malformed reason text is counted but never copied. An incomplete capture stays incomplete; an exporter-only update requires only `-Collect` on existing logs, never a new EFI boot.

Graph export v3 keeps device-path node types/lengths and PCI device/function numbers only under an explicit handle and DevicePath protocol record. All vendor/GUID, ACPI, storage, network and file payloads remain excluded. Fixed incomplete reasons also retain their position in the handle/protocol stream. These routing observations do not identify ownership automatically or authorize release; incomplete markers remain unchanged. Run only `-Collect` on existing logs for this exporter update.

A configuration may pin additional non-PCI Windows enumerators through `KnownNonPciAdapters`: each must appear exactly once and match one signed DISPLAY driver entry by exact device-instance association, provider and version. These are preparation identity observations, not firmware ownership or trust proof. Issue31 pins LCI/LuminonCore/1.0.2018.1204 from the returned Windows report. Missing, extra, changed, unsigned or unassociated entries stop preparation. ROOT/SWD behavior remains unchanged. No enumerator is globally permitted, and this data cannot enable release/unlock.

Configuration issue173 pins MSI MEG Z790 ACE (MS-7D86)/BIOS1.G0/i9-13900K, EVGA2216/3842:4897 and IntelA780/1462:7d86. Preserve direct RTX DisplayPort+HDMI connections and the TV's reported off state. Configuration issue185 pins ASRock A520M-ITX/ac/P3.90/RyzenPRO4650GE and ASUS2507/1043:887c as the sole Windows PCI display adapter; do not change the firmware/iGPU state or cable. The Windows-visible adapter list does not prove firmware iGPU absence. Both reuse the common graph-only test, not another GPU's unlock profile.

Configuration issue51 pins ASUS TUF GAMING X570-PLUS (WI-FI)/BIOS4002/Ryzen5900X and sole ASUS RTX3090 2204/1043:87b3. Keep both HDMI monitors and current settings unchanged. VBIOS94.02.42.00.b4/stock history and Secure Boot off are contributor-reported; preparation checks current policy/Windows identity. Matching GPU/VBIOS with issue38 does not qualify this board or its ownership graph. Use the same graph-only command with `-Machine issue51`, acceptance/backup/one-boot/stop/recovery and one-summary collection rules above. No probe MMIO or another machine's unlock profile is authorized.
