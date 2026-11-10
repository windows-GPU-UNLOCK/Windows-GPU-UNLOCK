# X570 AORUS ELITE F41c / RTX3090 FE resource research preparation

Status: source/build/staging preparation completed; attended-run proposal is held
until the owner reports whether the preceding graph boot returned directly to Windows.
The supplied graph hash1f04a81a939da4ed52aa93404edadf15ccbc904712bd75d1e837e246043d50ae
is complete/status0 and shows2204/147d10de at segment0/bus8/device0/function0, one GOP
protocol link. Windows return is not inferred from successful collection/upload.
Exact Windows pins: X570 AORUS ELITE/F41c/Gigabyte/5800X, one NVIDIA adapter.

A new issue172 data entry reuses the shared resource engine. No driver release,
GPU/PCI writes, decode enable, reset, GPU firmware execution/upload or unlock.
NEW boundary, not accepted by graph consent: PCI resource/attribute/parent reads,
16 fixed BAR0 DWORDs, full1MiB PROM (up to262160 direct MMIO reads), CPU-memory
loaded firmware-driver images, USB log and attempted Windows return. Reads may
have side effects, firmware/display/input may hang and Windows may fail to start.
Recovery is unproven. No automatic reboot/retry/rollback. A future attended proposal
must include power-off/USB removal/normal Windows Boot Manager recovery and no repeat.
Keep SecureBoot/encryption/display/settings unchanged; unknown/refusal stops.

Compiler-free resource template is separate from graph fixtures:31744B,
SHA f8a8b25ee0e8e02dcd0645f0a0285b7625cd3c302a6a0d5e34bd3f72e0c2e5ab.
It pins775 tracked source/header files and the production probe manifest; only16
Windows-ESP GUID data bytes at26624 can change. Device220410de/sub147d10de/bus8/
segment0 are compiled constants, not editable configuration overrides. Onlyissue172
may use this packaged path. Empty/sentinel GUID, changed source/image, wrong case
and existing output refuse. Never boot the raw template or a sample-GUID image.

Offline reproducibility (no compiler or hardware queries, existing source only):
```powershell
powershell -NoProfile -File .\research\profile\test-resource-template.ps1
```
Expected PASS for GUID-only data/source/scope/machine/staging/refusal checks. No
contributor rerun/artifact is needed to repeat local validation. If reproduced and
failed, return only short sanitized error and stop; preserve originals.

Validation: personalized sample exactly matches independently compiled image
SHA9027cf308e2bb89d288a8e1bd92259994db552a4b0be8c59cc4a9faf6ddb02e9,
AMD64 EFI31744B/zeroimports/NX/dynamicbase. Source/manifest/case/GUID/overwrite/corrupt
refusals, graph-log archive, loader backup/readback and no-repeat tests pass, alongside
existing shared resource preparation. No physical hardware run performed here.
The staging path additionally requires GRAPH-DIRECT before fresh ACCEPT-MMIO consent;
these are owner reports/acceptance, not independent recovery proof. No test-run request
authorized by this document alone; wait for the separately reviewed attended proposal.
