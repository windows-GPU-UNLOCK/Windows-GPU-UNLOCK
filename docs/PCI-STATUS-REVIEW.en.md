# PCI status comparison without private firmware

Issue36 reports one ASUS FX506HCB / GA107M `25a2/13FC1043` USB unlock
and a later HP `25a2/8A3D103C` inquiry with AMD `1638` display. These are
different machines. Neither report admits a profile in this repository.
The reported uniform-input MMA gains, failed closing FP16 control and
Windows Event153 failures must remain separate from generic GEMM/application
or stability claims. Windows Event153 is not automatically NVIDIA Xid153.

The current full-release comparison permits clearing previously set CED/URD
bits only in DWORD0x80 with the exact captured capability DWORD0x0012b410,
and only when checkCold=false. Other bit changes, newly set error bits,
different offsets or capability drift are refused. This existing comparison
is not the laptop's complete reported success/one-FLR/quiescence/cleanup rule.
Its acceptance cannot prove that those surrounding conditions occurred.

The existing whole-wrapper tests require private firmware fixtures. This new
runner extracts the actual bounded `VerifyConfigWord` function from trusted
local full-release.c and compiles it with a RAM-only mock captured config.
It tests4483 comparisons and detects four compiled guard-removal mutations.
No copied replacement policy, firmware files, captures or hardware are used.
Extraction or mutation-anchor drift stops for source review.

From the pinned checkout with existing Python3, clang and MSVC tools:

```powershell
powershell -NoProfile -File .\research\profile\test-pci-status.ps1
```

Use -Python, -Clang or -VcVars only to name already installed tools. No
installation or PATH policy change is required. Expected pci-status.json:
Passed=true, Assertions=4483, GuardMutationsDetected=4; HardwareAccess,
EfiExecuted, LaptopProfileAdmitted and WriteEligible all false. A new
Documents folder holds generated CPU test files; share only pci-status.json.
Stop on failure or unexpected true admission/hardware flags. Keep existing
settings and do not retry on hardware or boot EFI.

For the HP inquiry, a separately reviewed profile is research work, not a
transfer of the ASUS cold mask/PROM/capability pins. AMD versus Intel naming
does not establish preboot ownership or display routing. The exact HP model,
BIOS and firmware ownership remain unknown; no EFI probe is proposed for
intake, and unavailable data can stay unknown. This test advances source
review without requesting new captures or hardware execution.
