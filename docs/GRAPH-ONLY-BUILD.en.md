# Graph-only diagnostic build review

**English** | [한국어](GRAPH-ONLY-BUILD.ko.md)

Development preparation for #33. This is a **build-only test**, not instructions
to boot EFI. It requires Python and LLVM (`clang`, `lld-link`) on PATH.
From the extracted source folder, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\build-graph-only.ps1 -Fixture
```

Expected: `Graph-only build verified`. Review and return `manifest.json` and
`pe-verification.json` from `internal-boot\boot\build\graph-only`. Do not attach
the EFI binary or any firmware. If tools are missing, compilation fails or policy
blocks execution, send the short error with personal paths removed and stop.
Do not install tools or change policy solely for this optional check.

**Do not copy this fixture image onto a boot device or boot it.** It contains an
empty Windows partition GUID and cannot provide a qualified Windows handoff.
No USB is staged, boot entry created or settings changed by the build script.

The separate graph configuration excludes the deep-read probe and driver-release
sources. If eventually booted under a separately reviewed machine-bound plan,
the application would read protocol/open records, paths, GOP mode metadata,
console variables and 64-byte PCI headers; it would write a new diagnostic log
and attempt the existing Windows handoff. It does not read GPU MMIO/PROM, dump
driver images, release drivers or unlock. Firmware calls and the return path
remain hardware-unverified. This is not a complete local-profile capture.

The build uses an isolated generated header under its own output directory and
does not overwrite `platform-config.h` belonging to an existing setup. A separate
`-WindowsEspGuid` build is for reviewed development only, not authorization to
stage or boot an image. EN/KO docs and manifest claims describe source scope,
not proof that a specific firmware will behave safely.
