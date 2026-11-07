# Shared pinned resource capture: issue31

[한국어](X570-RESOURCE-CAPTURE.ko.md)

This is the next distinct hardware boundary after the existing graph-only logs.
Those two logs remain separate observations; accidental repeat does not erase
bytes, but filenames/results do not prove independent full-shutdown captures.
Do not repeat the graph test. Direct Windows return is contributor-reported.

Only: ASUS PRIME X570-PRO BIOS5013/Ryzen5950X, NVIDIA2204/10de:147d,
segment0/bus8/device0/function0, sole Windows PCI display adapter. Keep existing
ROOT/SWD adapters and LCI/LuminonCore1.0.2018.1204 signed-driver association.
These Windows metadata checks do not prove EFI ownership or release safety.
The same engine also serves issue114 through a compatibility entry point.

New scope after live identity/resource/callback checks: PCI resource/attribute
and parent observations,16fixed BAR0 DWORDs, one complete1MiB PROM window
(max262160direct MMIO reads), loaded firmware-driver image copies from CPU
memory, ownership/console graph and attempted Windows handoff. No GPU/PCI writes,
decode enable, detach, reset, GPU firmware upload/execution or unlock. Reads
may have side effects or hang firmware/display/input/Windows. Recovery is
unproven. Existing handoff disables the EFI watchdog. No automatic reboot,
retry or rollback. Explicit ACCEPT-MMIO is required before building/staging.

With Secure Boot already off, Python/LLVM on Windows, administrator PowerShell
and an existing FAT32 USB with256MB free, use fresh pinned source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-resource-capture.ps1 -Machine issue31
```

The script verifies exact machine/driver/configuration/USB and current Windows
ESP, builds an identity-pinned EFI and checks its PE/source manifest. It hashes
the configuration across compilation, rechecks machine/driver/USB/SecureBoot,
backs up and verifies the old loader, renames existing captures into a preserved
archive and verifies the staged copy. No formatting or boot-entry writes.
Mismatch, uncertain policy, missing tools or error: stop; report the short error
with personal paths removed. Do not edit guards or change settings.

After READY, fully shut down and manually boot this USB ONCE. No Shift keys.
Expect capture then Windows. If Windows has not started within2minutes, power
off, remove USB and use normal Windows Boot Manager. If recovery fails, stop
using the test. Do not repeat even if capture/refusal is incomplete.

After Windows returns, reconnect USB if needed and run the same command with
`-Collect`. Return only reviewed report.json from the printed Documents folder
and whether Windows started directly or required manual recovery. Keep original
and archived DIAG/PROM/IMG/EFI/backups local; remove USB afterward. An incomplete
or outside_scope result is reviewed before another step; no profile generation
or unlock is authorized by this capture.

Local validation:267generic+12exact Zotac+12exact X570 native mocks, configuration/
USB/archive/repeat refusals, four forbidden-build failures, both pinned fixture
builds and PE/source manifests. The X570 synthetic-GUID image is31744bytes,
SHA25632dda2435ba4d61c20e262717bc128e43c5ba2e1c1d0937a811cc796ffa55d6c.
NEVER boot fixture images; preparation builds with the owner's actual Windows
ESP. Local mocks/builds do not establish physical MMIO or Windows return.

Preparation now requires an observed fully decrypted system volume before build and immediately before staging. Protection off alone is insufficient. Encrypted/transitional/unknown/provider-failure states stop without settings changes. Do not suspend or decrypt for this test. Collection of existing files remains available.
