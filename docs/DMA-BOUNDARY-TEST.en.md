# Device DMA address boundary test (#54)

Run from pinned source with existing clang and MSVC/Windows SDK:

```powershell
powershell -NoProfile -File .\research\profile\test-dma-boundary.ps1
```

This reuses the production port's RAM-only test suite. New cases map4096 bytes
at0xfffff000 (last byte0xffffffff: accepted) and request4097 bytes at the same
address (rounded to8192: refused, unmapped/freed, no mock MMIO/config writes).
CPU allocation pointers and device-visible addresses are already distinct in
the suite. Production GuDmaAllocate maps a common buffer and checks its whole
device-visible range; AllocateAnyPages alone does not describe that range.

Expect the port suite PASS and dma-boundary.json in the printed Documents
folder. Return only that reviewed JSON if reproduced; maintainer already ran
it, so no contributor repeat is necessary. Missing tools/block/failure: stop
and return a short sanitized error. Use -Clang/-VcVars only for existing tools.
No dependency install, policy change, EFI/firmware, GPU access or reboot.

These mocks do not establish the deleted DXE binary's actual addresses, DMA
content visibility, coherency, an AD103 root cause or a qualified recovery path.
The original test artifacts are unavailable; do not reconstruct them by booting.
Also, probe-parent.c prints parents0 when available0: that is unavailable data,
not an observed zero-parent graph. No source admission or guard bypass follows.
# Contributor reproduction, 2026-11-02

[Issue54 comment6567031221](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/54#issuecomment-6567031221)
reports the v1 CPU-only boundary test passed on Windows using clang/LLVM23.1.4:
exact 32-bit end accepted, rounded crossing refused; hardware, EFI and write
flags false. This is a contributor-reported result, not an independently
observed run. The returned JSON contains no source hash. It does not verify
the later v2 six-case retained-cleanup/re-entry extension, physical AD103
behavior, an EFI root-port graph, unlock or recovery. No repeat is requested.
