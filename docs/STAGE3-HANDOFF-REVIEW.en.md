# Stage3 handoff: source review and retained DMA test

Issue21's public stage3 archive is 40,139 bytes, SHA256
`6b1087e4ec42835475bfb3c5781f2d9a9b52865614bb75f27a9cdba7321624cc`.
It was inspected as data, not built or executed. Its source chooses the first
3090 before checking FE subsystem, discards MMIO operation status, frees a
successful short/high DMA mapping without Unmap, and ignores teardown
Unmap/FreeBuffer results. These source observations do not demonstrate a
failure on the contributor's hardware. Current port.c already has checked
MMIO, device-visible DMA validation and retained-resource failure handling;
the old shim is not adopted or copied into this project.

The extended existing test_port.c suite exercises partial, high and misaligned
successful mappings with each of Unmap/FreeBuffer failure (six combinations).
It verifies retention, no premature free after failed Unmap, zeroed outputs
on rejected re-allocation, no further Map/Unmap/Free calls on re-entry, and no
GPU/PCI writes. Test-only resource disposal is not a production retry path.

Optional reproduction with already installed clang/MSVC:

```powershell
powershell -NoProfile -File .\research\profile\test-dma-boundary.ps1
```

Use -Clang or -VcVars only for existing tool paths. Expected native PASS and
new Documents/dma-boundary.json: Test=dma32-rounded-boundary-v2,
InvalidMapCleanupFailureCases=6, RetainedMappingRetryRefused=true,
HardwareAccess=false, EfiExecuted=false, WriteEligible=false. Share only that
JSON if reproducing; the maintainer has already run it. Stop on failure or
unexpected true hardware/write flags. Do not install dependencies, boot EFI,
retry the old handoff, repartition or change settings.

The contributor's reported byte-identical rebuild except five delay-patch
bytes has not been independently reproduced here. Reported sleep survival
and hibernation reset concern that implementation/host, not current support
or resume reliability. Firmware owner was explicitly unknown, not proved
unbound by the AMD display route. Original contributor requested no credit;
do not add a personal attribution or demand a new public repository. Full
source/provenance and exact-machine integration review remains separate.
