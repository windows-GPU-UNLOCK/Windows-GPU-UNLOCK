# Issue199: exact GA104/Intel preparation

Reported MSI PRO Z690-A WIFI (MS-7D25), A.A0, i7-12700, NVIDIA
2487/40741458 and Intel4680/7D251462 are separate exact graph-only pins.
HDMI on NVIDIA and an uncabled Intel adapter do not establish firmware GOP
ownership or recovery. The supplied PROM hash and16MiB BAR constants are
metadata, not independently verified bytes or source/build provenance.
No firmware dump, regenerated constants or new EFI intake run is requested.

Common configuration, mock staging/backup/readback/capture preservation and
packaged PE/source/hash tests passed locally for issue199. Shared preflight
status/privacy regressions also passed. Data cannot enable MMIO/release/unlock.

One primary Windows-only command from pinned source:

```powershell
powershell -NoProfile -File .\tools\test-windows-preflight.ps1 -ExpectedDevice 2487 -ExpectedSubsystem 40741458
```

Expected windows-preflight.json in a new Documents folder, SchemaVersion3,
target count, firmware-policy state, display-driver associations and bounded
system-volume encryption status, HardwareTested=false/WriteEligible=false.
Unknown or unavailable is acceptable. Share only that JSON. No recovery keys,
protectors, volume identifiers or device-instance suffixes are exported.
No compiler, installation, USB, EFI, reboot or settings change. On errors,
stop and return the short error with personal paths removed; do not change
Secure Boot, encryption or display configuration to pass a check. This prepares
a separately reviewed graph route; it is not a usable unlock profile or an
attended-run proposal. Source/firmware ownership and applicable acceptance
remain separate gates even if the Windows checks report expected values.
