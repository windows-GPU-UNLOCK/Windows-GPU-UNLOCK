# Christian MSI text-console Stop emulation

## Extended synthetic-state test — 2026-11-01

Christian confirmed no GPU/BIOS changes. The emulator now runs ten cases across the two saved captures. A supplied wrong child returns EFI_INVALID_PARAMETER. A matching child with an explicitly empty synthetic controller list and nonempty sibling state returns EFI_UNSUPPORTED and clears the emulated byte at RVA 0x60f9. The test originally checked 0x61f9; RIP-relative address calculation corrected that test offset before commit. These globals are constructed test inputs, not reconstructed live state. No callback/FreePool path is exercised or qualified by this result. The valid one-child/controller-present release remains unqualified; there is no new live EFI instruction for Christian.

[한국어](CHRISTIAN-STOP.ko.md)

The returned screenshot confirms the exact-driver pin test passed on both saved captures, with six negative pin cases per capture. This is not hardware release evidence.

The next developer test executes the exact captured text Stop at RVA 0x10bc in Unicorn x86-64 CPU emulation. Both captures pass three cases: zero children returns EFI_SUCCESS (22 instructions); two children returns EFI_INVALID_PARAMETER (23); one child with a null buffer returns EFI_INVALID_PARAMETER (25). Stack return is checked and instruction execution is restricted to the reviewed Stop range. No native firmware or hardware is accessed. The initial test expectation incorrectly used EFI_UNSUPPORTED for malformed arguments; disassembly at 0x125b and execution corrected it to EFI_INVALID_PARAMETER before committing.

Developer reproduction, with Unicorn installed: `python research/profile/test-christian-stop-emulation.py <saved-capture-directory>`. The local Unicorn dependency resides in user site-packages, so isolated `-I` is not used for this developer test. Firmware images remain data, not native executables.

These paths do not qualify the valid one-child removal branch, its linked-list updates or protocol callbacks. That branch must be reviewed and tested separately before preparing a release EFI. Christian does not need another capture boot or to install emulator dependencies. Preserve the existing captures and BIOS configuration.
