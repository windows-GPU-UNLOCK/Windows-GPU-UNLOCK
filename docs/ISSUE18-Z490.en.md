# Issue18 commenter: separate Z490 preparation

Reported MPG Z490 GAMING PLUS (MS-7C75), AMI A.B0, i5-10600KF,
RTX3060Ti2489/150A7377. These are not the opening ASUS B550 case or
issue80's Z690/40761458. Configuration data cannot admit 2489 to MMIO or
unlock, reuse another GA104 profile or establish GOP ownership. No iGPU exists
in the reported KF CPU; physical display/firmware ownership remains unknown.
The shared strict machine/unknown-adapter/policy/encryption guards remain.

Optional offline preparation test from pinned source:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue18-z490 -PackagedFixture
```

Expected PASS and new Documents/graph-build-test.json with selected configuration
issue18-z490/hash, ConfigurationTests and MockStagingTests=pass,
FixtureOnly=true, HardwareTested=false and WriteEligible=false. Share only
that JSON if reproducing. Maintainer validated it locally. Mock backup/readback/
capture-preservation tests use temporary files, not a real USB. No hardware
query, compiler, installation, EFI or settings change. Never stage/boot the
fixture. Stop on errors or true hardware/write flags; leave settings unchanged.

This answers the preparation question with a reproducible offline test, not a
non-destructive guarantee or an attended-run proposal. Any later firmware
diagnostic needs its reviewed exact scope, source/build and informed acceptance;
no BIOS changes, new EFI intake capture or profile bypass is requested.
