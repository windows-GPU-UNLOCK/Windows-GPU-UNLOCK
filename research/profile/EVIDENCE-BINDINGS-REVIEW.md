# PR #188 evidence-binding validation companion

Based on PR #188 head `2f654ccbda6eea3a767807f60b5010bd866e35cb`.

The reported-binding comparator could call a record consistent when both the
profile's Replay fields and corresponding audit fields were absent or null.
Python equality also allowed Boolean/float values to stand in for integer
format, count and segment fields. This changes a review verdict, not an unlock
or write decision.

The companion requires complete, correctly typed identity, replay and count
fields before comparing them. The CLI rejects duplicate JSON keys and
nonfinite numbers and bounds each actual read to 2 MiB plus one sentinel byte.
It still hashes the original profile bytes, including BOM/line endings, keeps
errors free of input values and paths, and leaves all input files unchanged.
Expected nonzero job exits remain valid when they equal their declared expected
result. `profile_admitted` and `write_eligible` remain false.

## Offline validation

From the repository root, using Python 3:

```sh
python -m unittest discover -s research/profile -p 'test_evidence_bindings.py'
python -m unittest discover -s research/profile -p 'test_*.py'
python -m unittest discover -s tools -p 'test_*.py'
python -m unittest discover -s benchmark -p 'test*.py'
```

The eight targeted methods include paired missing/null fields, exact numeric
and Boolean types, malformed objects, intentional refusal exits, duplicate and
nonfinite JSON, actual read bounds, and sanitized CLI output. Run against the
unmodified head, the expanded suite produces 37 failed assertions and 28
malformed-container errors. With the fix, all eight methods pass.

The full profile suite passes 118 tests, tools 14, and benchmark 28. An
independent source review found no blocking issue and checked 24 additional
synthetic valid records across segment and topology variants and maximum
numeric pins. Tests used fabricated local files and Python objects only.

## Limits

This checks consistency of reported bindings, not the independent truth of
source files, host test results, profile admission, recovery or hardware safety.
Complete Replay fields are now required; incomplete historical reports are
rejected rather than upgraded into complete evidence. The existing path-check
versus file-open race is not eliminated by the read-size cap. No PowerShell,
firmware, EFI, GPU, USB, registry or hardware operations were performed. This is
a review patch; release manifests are unchanged.
