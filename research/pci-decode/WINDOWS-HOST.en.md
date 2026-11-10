# Windows host validation

Run from pinned source with an existing Python3, clang and MSVC/Windows SDK:

```powershell
powershell -NoProfile -File .\research\pci-decode\test-decode-sync.ps1
```

If discovery needs help, use -Python, -Clang or -VcVars with tools already
installed. No installs, PATH persistence or policy changes are requested.
The script sets the compiler environment only in its child process, runs the
existing exact device/chip/memory/driver admission suite (including 6000a on
2204 and cross-family refusals), then runs the
shared core, adapter, capture/composition, owned-lifecycle and workspace suites,
plus all compiled guard mutations,
and writes a new Documents/GPU-Unlock-Decode-Host-*/run/summary.json.
The current runner requires all five host suites to pass and 34 compiled mutations
to fail their exact expected assertions. Running this command on Windows exercises
RAM-only mocks; it is not EFI ABI/hardware proof, production integration, profile
admission or Windows-return testing. The instructions are not evidence that this
integrated revision has passed on native Windows.
Return only reviewed summary.json if useful; the contributor need not repeat
tests already run by the maintainer. Missing tools or failure: stop and return
the short sanitized error. No capture, firmware, USB staging or reboot.
# X870/GA104 command/cache and Stop transition (#202)

The shared RAM model now transcribes reported GPU2484/f2781569 and parent1022:14db
at0:0:1.1, GPU command/status00100002/cache0300 and parent00100007/cache0700.
Unreported config words, BAR, supported masks and handles are synthetic. This
does not replay the private full capture or qualify that hardware.

The research cache-only path disables only the stale GPU IO attribute, leaving
GPU command00100002 and every parent field unchanged. A parent transition to
00100003/cache0300 is individually consistent but fails the exact before/after
baseline comparison. The reported stopped pair (GPU00100000/cache0 plus that
parent) also refuses without a correction callback. Parent BME clearing is
reported firmware behavior, not an accepted integration allowance or proof of
memory restore, payload/FLR, reconnect or no-reset Windows handoff.

The production LOCAL/CapturePermit route is unchanged; the correcting research
core is not wired into it. No other machine's pre-step/profile or bridge-BME
enable is authorized. For source review, existing sanitized Stop/snapshot-match/
claim-close code excerpts and exact private build identifiers would help if
available; no new hardware run or nonexistent post-release artifact is required.

## Evidence scope and source identity

The [independent Windows report](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/pull/192#issuecomment-6569927972)
is pinned to historical source `e5a4326`. It does not validate later commits or
this integrated tree. Separately, the source author's later documentation at
`8078ee9875b58f27e8721161859052bf307e9378` reported 65,388 core, 596,945 adapter,
52,197 capture assertions, 21 mutations and four family tests on Windows. That
later count claim is not the independently pinned report or current native proof.

The integrated executable sources, bound by the runner’s 24 repository-relative
source hashes, were checked only on Linux with GCC 14.2 through a wrapper adding
`-fshort-wchar`: 119,037 core,
1,541,757 adapter, 52,733 capture/composition, 822,653 owned-lifecycle and
1,553,181 workspace assertions, 34 exact-assertion mutants, seven runner regressions
and four family tests passed. This does not establish Windows toolchain, EFI ABI
or hardware qualification; native Windows validation of the integrated code remains
unverified.

The command above includes the command/cache fixture. Its summary records
reported_command_cache_pair_fixture_passed=true, private_capture_replayed=false,
parent_stop_transition_admitted=false. Hardware/EFI flags remain false.
