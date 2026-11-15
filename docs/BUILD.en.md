# Build and validation

**English** | [한국어](BUILD.ko.md)

Python 3.9+, LLVM/clang and lld-link are required. The successful-case EFI was built with **clang 20.1.8**. The default build is a read-only preflight and cannot run the unlock. It still contains exact-machine checks; it is not a generic hardware probe.

To build the experimental profile for the verified system:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\unlock\build.ps1 `
  -Clang C:\TOOLS\LLVM20\bin\clang.exe `
  -LldLink C:\TOOLS\LLVM20\bin\lld-link.exe `
  -ExperimentalUnlock -StockProfile entryLatchedSs1Full
```

Output:

```text
unlock/build/experimental/entryLatchedSs1Full/RTX3090-EXPERIMENTAL-entryLatchedSs1Full.EFI
```

The build checks PE/COFF structure. During original public preparation, a rebuild with clang 20.1.8 matched the successful USB EFI SHA-256. Compare a new build using `Get-FileHash`. `HardwareTested=false` in a new build manifest means the automated build did not test real hardware. Historical successful-case evidence is kept separately in `evidence/`.

## Offline PE file-backing regression

Both verifier copies check header/table bounds, nonoverlapping section ranges,
complete section raw bytes, and file backing for the executable entry and
relocation directory. A headers-only truncated file must not receive a successful
verification report. Zero-filled non-entry sections remain allowed.

```text
python -m unittest discover -s unlock/tests -p test_pe_file_bounds.py -v
```

This suite uses constructed PE bytes and a synthetic linker map on Linux or
Windows. It needs only Python, runs both verifier copies including their optimized
CLI, and never builds or executes an EFI image. The verifier establishes these
file-layout and existing identity/import/flag/map checks, not full PE loader
compatibility, relocation contents, signature trust, firmware behavior, GPU safety
or Windows recovery. Real builds and native firmware were not tested here.

Validation on Linux: the initial 11-test regression suite against main
`dc19de9` produced 36 failing and 10 error subcases; after the fix it passed.
The expanded 16-test suite passes normally and with `python -O`, covering both
copies, raw padding, zero-fill, exact ends, overflow and overlap refusals.
On invalid input the CLI returns nonzero and does not write a new report. An
existing output file is left unchanged; callers must check the exit status and
match the report hash to the current image, not treat file existence as success.
The existing build scripts stop when verification exits nonzero.

## Host mock checks

These tests do not access a GPU. MSVC/Windows SDK are required; use `-VcVars` if your Visual Studio path differs. The full command below requires local fixtures from the owning PC. PROM, raw captures and firmware are not published.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\unlock\test-all.ps1 `
  -Clang C:\TOOLS\LLVM20\bin\clang.exe `
  -VcVars 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat' `
  -WithLocalFixtures -ExperimentalUnlock -StockProfile entryLatchedSs1Full `
  -Assets C:\LOCAL-FIXTURES\assets `
  -Prom C:\LOCAL-FIXTURES\probe\PROM.BIN `
  -Capture C:\LOCAL-FIXTURES\probe\REPORT.TXT `
  -ColdCapture C:\LOCAL-FIXTURES\cold\REPORT.TXT
```

Do not report missing-fixture or partial validation as a complete pass. Historical `test-*.cmd` files and some old tests assume the original development environment; `test-all.ps1` is the current port entry point. Mock success does not prove GPU success or long-term stability.

## Historical release checks

During public preparation on October 20, 2026, **10 host mock groups and malformed-PE rejection checks** passed for this profile. The [recorded result](../evidence/host-tests.json) explicitly states `HardwareAccess=false`. The packaging tool's five tests also passed: successful packaging and rejection of bad assets, modified source, an existing output and path traversal. These are historical results, not a claim that this documentation update reran the hardware or full host suite.

To run the public Python tool tests without firmware or GPU access:

```powershell
python -m unittest discover -s tools -p "test_*.py" -v
```
