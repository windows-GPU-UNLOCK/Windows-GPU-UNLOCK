# Issue173 resource preparation: hardware execution not authorized

This source prepares a separately scoped resource diagnostic for MEG Z790 ACE
(MS-7D86), BIOS1.G0, i9-13900K, EVGA2216/48973842 at segment0/bus1/device0/fn0,
with Intel8086:A780/7D861462 retained. These pins come from the existing reported
graph, hash c1222d54c5487273fa6e9553e78ba8c57bfa5fe4100c14f27eeeedc738f2c242.
Its NVIDIA command3/BAR081000000 are observations, not resource-map proof.

The source explicitly admits this tuple only in an exact-pinned, explicit-bus1
generic diagnostic build. An unpinned generic build, wrong bus or403F1458
subsystem remains refused before MMIO. This does not copy PR118's other card's
hardware qualification, add general2216 admission, or change profile/write gates.
Graph configuration data alone cannot enable this boundary.

RAM mocks: generic269 checks; four exact-pin builds14 checks each (including
this EVGA tuple); wrong-bus/other-board research builds2 refusal checks each.
Missing pins, unlock/release/auto-bus build combinations and altered manifest
pins refuse. Exact board/BIOS/target/companion preparation mocks pass. The sample
Windows-GUID image is31744 bytes, AMD64, zero imports, NX/dynamic-base, SHA256
32ad49b611ae6d7e1a67ac2e288e5bee785fc003cd79e33d595ef246972c797b.
That sample image must never be staged or booted. It is not the owner's image.

The shared offline runner can select this exact fixture in a fresh source folder
with an already installed Python/LLVM/MSVC host environment:

```powershell
powershell -NoProfile -File .\research\profile\test-zotac-probe.ps1 -FixtureMachine issue173
```

Existing -Clang/-LldLink/-VcVars options select known local tools. Stop if tools
or script policy block it; no installation or policy change. Expect all mock,
forbidden-build and PE/manifest groups PASS. Return only PASS or a short sanitized
failure if reproducing; no repeat is needed for maintainer validation. The final
sample11111111 GUID image built with clang21.1.6 is SHA256
b95e146eff7d55ffde13151184dd6f131163c1c5c6999474739339d16212b365.
Compiler/GUID differences can change bytes; neither sample hash is owner proof.

The shared preparation script already supplies backup/archive/readback/no-repeat
gates and acceptance prompt. No real media was staged. A future attended proposal
must separately explain PCI resource/attribute/parent callbacks, sixteen fixed
target BAR0 DWORD reads, up to1MiB PROM-window reads and loaded-image CPU copies;
possible read side effects, firmware/display/input hang and Windows-return failure;
and a manual stop/recovery plan. No MMIO permission, driver release, reset, GPU
write, firmware execution/upload, profile generation or unlock is granted here.
No automatic reboot/retry, settings/cable/iGPU changes or graph recapture.

Before any attended instructions: re-read the latest case, review this source
and exact build/evidence collection, and obtain the applicable informed acceptance.
Current Secure Boot/encryption policy must be checked without changing it. The
Intel adapter's header/BME observation is not proof of a recovery display.

The sixteen target BAR0 DWORD offsets are000000,108154,108170,108180,108354,
118128,118234,110100,1183a4,1fa828,8219c0,822804,823804,82381c,823820,824140;
the PROM window is300000..3ffffc, up to262160 reads total. The inherited Windows
handoff disables the EFI watchdog. A future accepted run would keep the TV off,
Intel enabled and cables unchanged, collect reviewed report.json using the
existing alternate local OutputRoot because Documents previously failed, and
retain raw DIAG/PROM/IMG/EFI/backups locally. Windows not started within two
minutes: proposed recovery is power-off/remove USB/normal Windows Boot Manager;
it is unproven. Stop if recovery fails; no automatic or manual repeat without review.

The existing issue172 template was independently rebuilt with the sample GUID
and matched its previous personalized bytes exactly. Only its source-hash
metadata changed; its publication/acceptance hold remains in force.
