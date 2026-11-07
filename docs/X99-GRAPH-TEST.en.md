# Issue 33: attended X99 graph capture

**English** | [한국어](X99-GRAPH-TEST.ko.md)

Only for ASUS X99-PRO/USB 3.1 BIOS 4101, i7-5820K and the sole ASUS RTX 3090
`2204 / 1043:87af` reported in #33. This is a graph diagnostic toward a profile,
not an unlock or complete profile capture. No GPU MMIO/PROM reads, driver image
dumps, driver release, GPU writes or firmware-variable writes are added.

The EFI reads firmware protocol/open relationships, console variables, GOP mode
metadata and PCI headers; writes a USB log; and attempts Windows Boot Manager
on the current system ESP without reset. It disables the EFI watchdog as the
existing handoff does. Firmware calls or handoff may hang, lose display/input
or fail to return to Windows. Recovery is unproven. There is no automatic retry
or rollback. Use only an attended machine whose owner accepts that boundary.

## Prepare once

Use an existing FAT32 USB data stick, Python and LLVM (`clang`, `lld-link`).
Secure Boot must already be off. Do not change settings for this test. Extract
the pinned test source and open PowerShell as administrator in that folder
(the script reads Secure Boot and disk metadata; it never formats a disk).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-x99-graph.ps1
```

Enter the USB drive letter. The script checks the exact Windows machine tuple,
USB bus/filesystem/system-disk exclusions, existing Secure Boot state and current
Windows ESP. Read the risk message and type `PREPARE` only if you accept it.
It builds a pinned EFI, preserves and verifies any old USB boot loader, refuses
existing capture files, and verifies the final USB copy. It does not reboot.

Expected: **READY**. If anything fails or organizational policy blocks the
script, stop and report the short error with personal paths removed. Do not
change settings, bypass guards or retry blindly. Partial preparation and backups
are retained for review.

## Run once and return evidence

Fully shut down. Manually select that USB once from the firmware boot menu.
No Shift keys or other test hotkeys are required. Expect graph capture followed
by direct Windows boot. If Windows has not started within two minutes, power
off, remove the USB, then select normal Windows Boot Manager. If recovery fails,
stop using the test. Do not repeat the run.

In Windows, reconnect the USB if removed, then run the same script with
`-Collect`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-x99-graph.ps1 -Collect
```

Enter the USB letter again. Attach only the reviewed **graph-summary.json** from
the printed Documents folder, and say **Windows started directly** or **manual
recovery was required**. Keep raw DIAG logs, EFI and backups local. The summary
contains allowlisted numeric relationships/PCI headers, hashes and completion
markers; raw device/file paths are excluded. Remove the USB after collection.
The markers are observations, not proof of a successful profile or safe release.
The graph will guide the next separately reviewed resource/driver qualification.
