# Existing NVIDIA firmware-code review

Issue203 already reports two complete captures and a GA106/6000a driver-scope refusal. Do not request another capture or copy a GA102 allowance into GA106. Current main fd8bbea admits hash8924ba488419e5d82b524d10e8dd63bfe886f077026fae1a9cc03e25b920b276/version6000a for2204 only; GA106 remains60010. The reported prefix alone does not verify full code identity.

```powershell
powershell -NoProfile -File tools/test-existing-nvgop-code.ps1
```

Select the same existing folder containing DIAG and IMG files. The tool reuses make-profile's binding/PE/relocation/code-range checks. It reads image bytes as data only and exports full image/code hashes, version, code length/RVA and Stop offset. matching_family_code_entries refers only to the checked-out envelope, not current upstream or card qualification. No memory addresses, personal paths or raw firmware bytes are returned. A hash identifies bytes, not release behavior or hardware safety.

Return only reviewed nvgop-code-review.json from the printed folder. Expected test existing-nvgop-code-v1, code_only true, hardware_verified/driver_release_verified/write_eligible false. Exact hash equality and consistent metadata across existing captures are evidence to review, not admission. Unknown/changed code stays unreviewed. Stop on error/policy block/missing files; preserve originals and report the short sanitized error. No installs, settings, new EFI/capture, profile flags or hardware experiments.

Three local synthetic tests passed: full identity/cross-family distinction; duplicate/missing/truncated/out-of-code Stop refusals; false authorization/privacy flags. Actual PowerShell launcher passed on a synthetic saved image. Contributor files were not replayed here.
