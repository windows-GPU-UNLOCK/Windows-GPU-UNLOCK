# Issue 114: one attended GA106 resource/PROM capture

**English** | [한국어](ZOTAC-GA106-CAPTURE.ko.md)

For Gigabyte B650M DS3H BIOS F21, Ryzen 5 7600, Zotac RTX 3060 Twin Edge
`2504 / 19da:2630` and the reported enabled AMD companion. Keep all three
monitors on NVIDIA and the AMD output uncabled. The AMD adapter's vendor/presence
is checked; its exact PCI tuple is not qualified and its MMIO is not read.

The old `c403e8f` probe refused this NVIDIA identity before deep reads. This new
test uses the reviewed generic GA106 read path with **additional EFI pins**:
device `250410de`, subsystem `263019da`, segment 0, bus 1, device/function 0.
Other reviewed generic IDs are still refused by these extra pins. The original
class/command, 16 MiB BAR0 resource and capability/state checks remain in force.
This is capture only: no profile generation or unlock staging.

## New boundary

After the live guards pass, the diagnostic reads PCI resources/attributes/parent
state, then these 16 BAR0 DWORD offsets once:

```text
000000 108154 108170 108180 108354 118128 118234 110100
1183a4 1fa828 8219c0 822804 823804 82381c 823820 824140
```

It also reads the 1 MiB PROM window `300000..3ffffc` once (up to **262,160 direct
MMIO reads total**), saves PROM.BIN and copies loaded firmware-driver images
from CPU memory. It records firmware ownership/GOP metadata and attempts the
existing Windows handoff. The existing handoff disables the EFI watchdog.
The diagnostic adds no GPU/PCI writes, decode enable, driver detach, GPU reset,
GPU firmware upload/execution or unlock. Reads can still have side effects or
hang. Display/input/firmware/Windows may fail; recovery is unproven. Manual
power-off/USB removal may be needed. No automatic retry or rollback.

## Prepare and run once

Use a fresh extraction of the pinned source, Python/LLVM and an existing FAT32
USB data stick with **256 MB free**. Secure Boot must already be off. Open
administrator PowerShell in the extracted folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-zotac-ga106.ps1
```

Enter USB letter and type **ACCEPT-MMIO** only if you accept the new boundary.
The script checks the Windows-reported platform/NVIDIA tuple/AMD companion,
current Windows ESP and USB identity; builds and PE/source-manifest-verifies
the pinned image; verifies the previous USB boot-loader backup and final copy.
Old `RTX3090-UNLOCK` captures are preserved by a same-volume archive rename;
the new run gets a separate folder and marker. Nothing is formatted or rebooted.
It refuses to restage its own marked run. On error/mismatch/policy block, stop
and report the short message with personal paths removed. Do not change settings
or bypass a guard.

After **READY**, fully shut down and manually select this USB once. No Shift
keys are needed. Expect collection then Windows. If Windows has not started
within two minutes, power off, remove USB and use normal Windows Boot Manager.
Stop if recovery fails. Do not repeat the run, even if it appears successful,
until its evidence has been reviewed.

## Return one file

In Windows reconnect USB if needed and use the same script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\prepare-zotac-ga106.ps1 -Collect
```

Attach reviewed **report.json** from the printed Documents folder and state
**Windows started directly** or **manual recovery required**. Keep all raw
DIAG/PROM/IMG/EFI files and archives local; remove USB after collection. If Python
resolves incorrectly, `-Python` accepts your known-good executable path.

The report wraps the compatibility result and privacy-limited capture markers.
One successful capture can still show `needs_data`/`capture_count` because the
profile route requires two agreeing captures; **do not obtain the second now**.
An envelope refusal marker does not identify which guard failed. No result here
grants write eligibility. Next work is evidence/code qualification, then a
separately scoped profile stage, not automatic unlock.

Maintainer CPU/mock checks, in a fresh source folder and developer compiler
environment: `research/profile/test-zotac-probe.ps1` (optional `-VcVars` path).
Its fixture Windows GUID is synthetic: never stage or boot that test artifact.

Preparation now requires an observed fully decrypted system volume before build and immediately before staging. Protection off alone is insufficient. Encrypted/transitional/unknown/provider-failure states stop without settings changes. Do not suspend or decrypt for this test. Collection of existing files remains available.
# Preparation identity correction

Resource configuration schema2 pins the companion PCI display adapter by vendor,
device and subsystem, not vendor alone. Issue114 requires AMD1002:164E /
D0001458 alongside NVIDIA2504/263019DA. Missing, duplicate, another AMD device,
another subsystem, incomplete/wildcard companion data and old schema1 inputs
refuse before staging. The bundled no-companion configurations explicitly keep
all three companion fields null; source/config revisions must stay together.
This restricts preparation only. It adds no MMIO, release or unlock permission,
does not establish preboot recovery on the uncabled iGPU, and requests no repeat
capture. The separate issue172 publication hold remains in force.
