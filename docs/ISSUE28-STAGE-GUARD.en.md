# Issue28 / PR72 stage guard review

PR72 head `80db48e90d0b684efe7fc2b78e71ebe8759d014c` adds NVIDIA stage5 for B760 but excludes stage4 from `Profile` unconditionally. Existing configurations retain NVIDIA stage4, so that predicate removes their per-stage recheck. Skip only the B760 optional consumer role; preserve NVIDIA checks for every topology. This is source review, not a demonstrated hardware failure. No contributor code or firmware was executed.

EDK2 defines0x8 as `EFI_OPEN_PROTOCOL_BY_CHILD_CONTROLLER`; GUID `1c0c34f6-d380-41fa-a049-8ad06c1a66aa` is standard `EFI_EDID_DISCOVERED_PROTOCOL`. Neither constant proves edge ownership or code identity. The Maxsun hardware outcome remains owner-reported; the rebased wrapper has no reported physical validation. Do not transfer its profile to the separate Gigabyte case.

Run from this pinned source checkout, with the existing Clang/MSVC host toolchain available:

```powershell
powershell -NoProfile -File research/profile/test-local-release.ps1 -Card 0x250410de -Children 2 -Mutations
```

Use existing `-Clang` and `-VcVars` parameters if the compiler is not on PATH. Do not install or alter policy to run this test. Eight baseline RAM cases must pass; one compiled skipped-stage4 mutation must be detected through an assertion, not a crash. Local validation produced6542 checks per EDID case and4959 per no-EDID case. The mutant failed the consumer/path/code guard assertion. This models an old-topology regression; it does not validate the new B760 optional consumer or unlock hardware.

Return only the reviewed generated `build/local-release-<id>/summary.json`: `synthetic_only=true`, `hardware_access=false`, eight case results and `mutations` containing `skip-stage4-profile`, `compiled=true`, `detected=true`. No captures, firmware or private headers are needed. Stop on policy/compiler/test failure; retain the summary if available and report the short error. No EFI boot, hardware repeat, guard relaxation or recovery action is part of this RAM test.
