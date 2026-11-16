# Aggregate fixture review, 9 November 2026

This companion branch is based on upstream `dc19de9204df9b58d6eaa5b0e4697e0657b617de`.
It consolidates host-fixture work already proposed in [PR #302](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/pull/302)
and [PR #225](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/pull/225),
with capture-free regression coverage for [issue #368](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/368).
It is not an EFI package, hardware qualification, or request for another boot.

## Findings and attribution

- Sergey Litvinov's PR #302 (`2e99eb798fbf9254fbfe31a2cb147eda4f7d671b`) identifies
  the production driver-line format, continued image-path nodes, and target-edge
  ordering. Its target-edge normalization is retained here.
- On that exact PR head, `python -I research/profile/test_aggregate_topology.py`
  fails one of nine test methods: the revised path reader drops the second
  `image-file-path-node` marker used by the existing synthetic capture model.
- cfigueiroa's PR #225 (`60f05e0b2edf6b1d275ea6878fc4091c2f83bb04`) preserves both
  path formats and checks the emitted version/Stop metadata. Its nine aggregate
  topology tests pass. This branch uses those validation requirements and keeps
  the complete path terminator rather than excluding it from comparison.
- Issue #368's two parser failures match the inspected source. Its later
  `mode=0 calls=0` message alone does not identify the failed fault scenario or
  prove that its intact hardware graph was rejected. Its private captures were
  not reviewed here.

## Changes

- Accept the legacy synthetic driver line and the complete current diagnostic
  line, checking image, binding, version, and Stop address against the binding
  table. Reject incomplete, duplicate, conflicting, or trailing records.
- Read one complete contiguous image path in either emitted format. Preserve
  the end node; reject missing, interrupted, mismatched, or repeated paths.
- Put the unique target PCI I/O BY_DRIVER edge first for existing fault-injection
  tests without dropping unrelated ownership records.
- Add `research/profile/test_aggregate_fixture_formats.py`, covering both formats,
  one/two children, metadata refusals, path refusals, and unrelated-first handle
  enumeration.

## Validation on the final source

Python 3.12.14, Linux:

```sh
python -m unittest discover -s research/profile -p 'test_*.py'
# 114 tests passed, including the 4 new test methods.
python -m unittest discover -s tools -p 'test_*.py'
# 14 tests passed.
python -m compileall -q internal-boot/boot/make-console-fixture.py research/profile/test_aggregate_fixture_formats.py
git diff --check
```

The new tests were also run against unchanged upstream `dc19de9`: current-format
positive cases fail at the reported graph/binding mismatch. Existing aggregate
topology tests pass on that upstream source, demonstrating the earlier coverage
gap rather than an already-failing baseline.

Additional native RAM-only `test_aggregate_prepare.c` runs used GCC 14.2.0,
synthetic current-format records, and unrelated-first handle enumeration:

- `GU_PROFILE_B660M_3090TI`: 1,618 checks, one child, 28 scenarios passed.
- `GU_PROFILE_B660PLUS_3060`: 1,916 checks, two children, 28 scenarios passed.

Moving the normalized target edge behind unrelated edges in the generated
two-child fixture made the same native prepare test fail with
`aggregate prepare accepts only intact graph and successful durable logs mode=0 calls=0`.
The fixture was restored afterward. This reproduces that message without a
hardware refusal; it does not establish the cause of #368 without its inputs.

These builds used the existing test profile values, zero partition GUIDs, and
`GU_AGGREGATE_CAPTURE_FIXTURE`. GCC's existing misleading-indentation warnings
were retained as warnings using `-Wno-error=misleading-indentation`; all other
enabled warnings remained errors. No production source was changed to silence
the warnings.

## Limits

Clang and Windows PowerShell were not available here. The full Windows
`test-profile.ps1` job matrix, Clang/VFS-overlay release tests, EFI builds,
contributor-specific replay, and physical recovery were not run. Python and RAM
tests do not establish GPU compatibility or write eligibility.

No capture, firmware image, PROM, GPU register, boot setting, USB, or ESP was read
from or changed on a contributor's machine. Production firmware/runtime sources,
the proven envelope, and LOCAL evidence gates are unchanged. The repository
release manifest was not refreshed: this is review source, not a release package.
