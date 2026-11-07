# Issue197: MSI B650 exact graph preparation

Prepared pins: MAG B650 TOMAHAWK WIFI (MS-7D75), BIOS1.R3, Ryzen7800X3D,
2504/397D1462 and164E/7D751462. #114/#136 are different configurations.
Both monitors are reported on NVIDIA; firmware GOP/CSM remain unknown. The
uncabled iGPU is not established recovery. Fast Startup remains unchanged.

The common offline graph test passed this configuration, mock USB backup/
readback/capture-preservation guards and packaged PE/source/hash checks.
No physical media or EFI execution was used. The next missing prerequisite
is system-volume encryption status; no new capture or profile yet exists.

One primary Windows-only command from the pinned source:

```powershell
powershell -NoProfile -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2504 -ExpectedSubsystem 397D1462
```

Expected windows-preflight.json in a new Documents folder, SchemaVersion3,
target match count, SecureBoot, display-driver association and bounded
SystemVolumeEncryption status. Protection off is not necessarily decrypted.
Unavailable remains unknown. No recovery keys, protectors, volume identifiers,
raw device suffixes or provider error strings are queried/exported. Share
only that JSON. No compiler, USB, installation, settings change or reboot.
On error stop and return the short error with personal paths removed.

Shared preflight mocks test encrypted/protection-off, unavailable-provider
privacy and fully decrypted observation; encryption guard has13 cases. Actual
local Windows export was checked, not the contributor's machine. All reports
retain WriteEligible=false. Do not suspend/decrypt or change Secure Boot/CSM/
Fast Startup for this test. After review, an attended graph-only plan requires
explicit scope/acceptance and existing preparation stops; inventory is not
authorization for MMIO, driver release or unlock. No attended boot is proposed here.
