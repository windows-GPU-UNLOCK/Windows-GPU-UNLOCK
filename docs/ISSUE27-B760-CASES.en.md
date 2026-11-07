# Issue27: distinct B760 commenter configurations

| Configuration | Board / BIOS / CPU | NVIDIA tuple |
|---|---|---|
| issue27-b760-gigabyte | B760M DS3H DDR4 / F16 / i5-12400F |2786/41271458|
| issue27-b760-msi | PRO B760M-E DDR4 (MS-7D48) / B.I0 / i5-13490F |2786/20007377|

Both are inventory-only reports. These are separate from the opening MSI
1462:5138 machine and the B550M/1462:5136 collector-tested machine. Reported
inventory cannot establish physical route, firmware ownership, cold state or
recovery. Unknown policy/display/VBIOS details remain unknown; no new EFI
capture or settings/adapter changes are requested to complete intake.

Each new data configuration reuses the common graph-only preparation engine.
No per-card code, MMIO/probe admission, release, payload or unlock is enabled.
Unknown/extra adapters and wrong board/BIOS/CPU/subsystem remain refused.

From pinned source, choose the one command matching your reported machine:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue27-b760-gigabyte -PackagedFixture
```

For the MSI B760M-E case only, use -Machine issue27-b760-msi instead.
Expected PASS and new Documents/graph-build-test.json selecting that exact
configuration/hash, configuration/mock-staging pass, FixtureOnly=true,
HardwareTested=false and WriteEligible=false. Share only that JSON if
reproducing. Both runs passed locally. No compiler, hardware query, real USB,
installation, EFI, reboot or settings change. Never stage/boot the fixture.
Stop on any error or true hardware/write flag and leave settings unchanged.

This is exact preparation validation, not AD104 Windows unlock eligibility.
An attended firmware plan still needs source/ownership/policy review and its
applicable informed acceptance. No guaranteed recovery/universal support is
inferred from external engine advertising or another GA104/AD104 result.
