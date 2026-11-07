# Why local-profile unlock currently requires USB (issue191)

Manual boot-menu selection and loaded-image media identity are different inputs.
The USB build checks the device path of the volume from which the EFI was loaded;
it does not query how the user selected it. Internal media selected manually still
lacks the required USB path node and is refused by that build.

This is an enforced deployment/volume-binding contract, not a universal claim that
USB hardware is safe or internal media is intrinsically unsafe. In GU_USB_MEDIA /
GU_USB_PROBE, handoff Prepare() derives the log/child volume from OwnDevice, requires
USB ancestry, resolves the separately pinned Windows ESP uniquely, rejects windows==own,
and verifies the loaded Windows image's DeviceHandle. Child verified bytes are loaded
from the same experiment volume with a matching DeviceHandle. These invariants address
volume/child/return-path binding in addition to the chosen validated deployment surface.
They do not establish GPU/firmware/recovery safety.

The source also contains internal-partition branches using GuInternalPartition and
unique partition lookup. That does not make internal media an approved generated-local
write route: Get-LocalProfile sets UsbOnly=true, and build.ps1 rejects ExperimentalUnlock
without UsbMedia for such profiles. Existing internal/fixed-profile code cannot simply
be borrowed for a different local profile. USB removal is a concrete recovery option;
manual selection of an internal copy alone does not validate its volume/return contract.

An internal local-profile route would require a separately reviewed build/deployment
contract, partition/volume/child binding, source/evidence receipts, cleanup/Windows-return
and recovery tests, without changing hardware profile/admission guards. This note makes
no roadmap commitment and supplies no bypass or installation instructions.

Offline native production-header test (existing LLVM/MSVC/Python only):
```powershell
powershell -NoProfile -File .\research\profile\test-media-contract.ps1
```
Expected10checks/failures0. It covers pinned internal allowed only with InternalAllowed,
USB-required refusal, distinct Windows pin, valid USB and malformed/multi-instance/null
path refusals. It compiles a native RAM-only mock, not EFI, and does not call firmware,
GPU or disk APIs. Local run passed; this is not an internal boot/recovery test.
If tools are missing or it fails, stop without installing/changing policy or booting.
No contributor rerun/file needed to confirm an already-run result; if reproduced and
different, return only short sanitized output/error.

Source anchors: internal-boot/boot/media.h, handoff.c Prepare/LoadUnlock;
internal-boot/unlock/app_io.c UsbPath; local-profile.ps1 Get-LocalProfile; build.ps1.
