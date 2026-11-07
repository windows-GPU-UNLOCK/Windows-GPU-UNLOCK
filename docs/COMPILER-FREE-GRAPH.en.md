# Compiler-free pinned graph preparation

-PackagedGraph uses a separately packaged graph-only template, not the existing
nonbootable zero-GUID fixture. Template SHA256 is
7070d624c00cb4d194ae03626f336ae0b02b279716ffb42f6b53cf5609c5ee60.
The module pins the template manifest and all761 recorded tracked C/header inputs.
Only16 bytes at file offset10752 are personalized to the live internal Windows ESP
GUID, in UEFI byte order. Empty/sentinel GUIDs, source/byte changes or existing output
refuse. The code/PE bytes outside that field cannot change. This is data personalization,
not a local compilation; manifest BuildPerformed=false. Never boot the raw template.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-machine-graph.ps1 -Machine issue172 -PackagedGraph
```
No compiler/install/PATH change is needed. All existing exact machine/display,
SecureBoot-already-off, fully-decrypted volume, unique Windows ESP, USB identity,
PREPARE informed acceptance, backup/readback, empty capture and one-run stops remain.
The GUID stays local. No automatic shutdown/reboot/retry or firmware-variable writes.
The graph hardware boundary is unchanged: protocol/GOP metadata, console variables,
PCI headers, USB log and attempted Windows return; no MMIO/PROM/images/release/unlock.
Firmware/display/input may hang; Windows return/recovery remain unproven on this case.

Only after READY and the owner's acceptance: manually shut down and select the USB
once. If Windows has not started in2minutes, power off, remove USB and use normal
Windows Boot Manager; stop if recovery fails, no retry. Collect the existing log with
the same command plus -Collect (existing Python needed only then); return reviewed
graph-summary.json and direct/manual Windows outcome. Keep EFI/log/backups local.
Any mismatch/error: stop without installing, editing guards or changing settings.

Validation: separately compiled sample-GUID image and personalized image are byte
identical (SHA7974eb71bfd46eec67672d31ee437d34b1da1c248082f7b0fc25179ff8765b52).
Verified AMD64 EFI14848bytes/zeroimports/NX/dynamicbase. GUID-only byte order,761source
pins, empty/sentinel/existing-output/missing-source/corrupt-image refusals and existing
mock preparation/backup/capture preservation passed. No physical boot performed here.
The older graph-only.fixture remains nonbootable and is never used by this option.
