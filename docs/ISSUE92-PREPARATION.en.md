# Issue92: exact graph preparation with Parsec unresolved

Reported B550M AORUS ELITE / FHb / 5900X /2208:40851458, EAGLE OC
GV-N308TEAGLE-OC-12GD, factory VBIOS94.02.71.40.49, HDMI on NVIDIA.
The owner identifies source c403e8f0002ec69fc162a145d8172b2782ec9645 separately
from reference release v0.3.1. No EFI/refusal log exists; do not demand one.

New data configuration issue92 uses the common graph-only engine. Parsec
0.45.0.0 has no reviewed firmware identity. Null/ROOT/SWD fixtures remain
refused even with a signed driver label. Do not remove/disable it or bypass
guards; software display is not recovery or preboot ownership evidence.

Optional CPU/file-only command from pinned source, no compiler required:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue92 -PackagedFixture
```

Expected PASS and graph-build-test.json in a new Documents folder, selected
configuration issue92 with its SHA256, ConfigurationTests/MockStagingTests=pass,
FixtureOnly=true, HardwareTested=false, WriteEligible=false. Share only that
JSON if reproducing; maintainer already ran it. Mock backup/readback and
capture-preservation tests use temporary files, never actual media. No hardware
inventory query, EFI execution, installation, settings change or reboot.
Never stage/boot the zero-GUID fixture. Stop on errors or unexpected true
hardware/write flags and leave settings unchanged. This delivers preparation
and refusal validation, not unlock admission or a proposed attended run.
