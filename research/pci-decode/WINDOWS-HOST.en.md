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
existing shared core/adapter/capture suites and all compiled guard mutations,
and writes a new Documents/GPU-Unlock-Decode-Host-*/run/summary.json.
Expect all host suites PASS and21 compiled mutations detected on the PR139
merged source. These are native Windows RAM-only mocks, not EFI ABI/hardware
proof, production integration, profile admission or Windows-return testing.
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

New validation:65388 core +596945 adapter +52197 capture assertions,21 compiled
mutations detected and4 exact-family tests passed on Windows. The same primary
command below includes this fixture and writes summary.json with
reported_command_cache_pair_fixture_passed=true, private_capture_replayed=false,
parent_stop_transition_admitted=false. Hardware/EFI flags remain false.
