# Turing layout inputs: CPU-only research

Issue115 asks about RTX2080Ti. The pinned [Linux source7eb51bcc](https://github.com/Zagitta/gpu-unlock/tree/7eb51bccae0a0b7e599e084d971170e9a1e82d0c)
lists Turing experimental and includes an explicit TU102 family. This is not
Windows qualification. Current Windows gpu-family.h has no TU102 admission;
shared TU102 routine names in vendor comments do not supply that family.

Source review found layout_610.c/h identical after line-ending normalization.
The missing input contract differs: Turing derives usable framebuffer from
range magnitude/scale/ECC, rather than using the Ampere framebuffer/MMU inputs.
This research-only header models the reviewed arithmetic on supplied integers,
including VGA fallback and invalid/sentinel refusal. It is deliberately stricter
than the Linux reader about unknown range bits. No real Turing capture establishes
those restrictions or firmware readiness here. The synthetic0x2c8 example means
44 times2^28 bytes (11GiB), not an observed RTX2080Ti register.

No production target includes this header. Existing layout_610.c is unchanged;
no card catalog, MMIO reader, firmware/payload, driver release or unlock changes.

With existing clang/MSVC, from pinned source:

```powershell
powershell -NoProfile -File .\research\turing\test-layout-inputs.ps1
```

Use -Clang/-VcVars only for existing tool paths. Expected PASS for2016 synthetic
range combinations, VGA/sentinel/unknown refusals and actual unchanged layout
calculator; turing-layout.json in a new Documents folder, Passed=true and
hardware/captured-evidence/EFI/profile/write flags false. Share only that JSON
if reproducing; maintainer already ran it. No Python, compiler installation,
captured files, GPU query, EFI, reboot or settings change. Stop on failure or
unexpected true hardware/admission flags; no hardware retry.

This advances an isolated arithmetic gap, not a Turing transaction. Firmware
descriptor/loader/FWSECv2, exact card/board/cold pins, ownership, release,
cleanup/Windows return and matched performance remain separate review gates.
Do not adapt another card's registers or boot an Ampere profile to fill them.

## Research v2 metadata follow-through

The same runner now also tests `fwsec-v2-metadata.h` against synthetic descriptor
bytes: accepted secure/nonsecure IMEM split, exact descriptor+image boundary,
and79 truncation/overflow/geometry/unknown-field refusals. Failed outputs are
zero. The report is turing-layout-input-model-v2 with MetadataRefusalCases=79.
The v1 result/pin previously supplied to issue115 remains a separate result.

This is not an extension of production vbios_610.c, which still refuses v2.
It is a research metadata subset of the pinned Linux descriptor contract:
zero generic-loader entry/DMEM base, zero unreviewed tail fields and nonzero
secure code are deliberately required. Real firmware may require a different
reviewed contract; no captured Turing firmware qualifies these assumptions.
No firmware assets are needed, copied or emitted. No container walking,
signature/authentication validation, loader integration, image patching or
execution is implemented. Production v3 behavior and card guards are unchanged.
