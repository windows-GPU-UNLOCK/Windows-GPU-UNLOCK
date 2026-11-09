# Offline diagnostic graph framing review

This review concerns recorded syntax, not hardware qualification or unlock safety.

## Producer order and reproduced defect

`internal-boot/boot/diagnostic.c` writes the graph header in
`GuCaptureGraphOnVolume`, then the optional `GuProbeGpu` observations and the
handle/protocol/open/detail records. It writes `capture-complete=1` only after
handle re-enumeration and cleanup. The diagnostic branch in `handoff.c` writes
`diagnostic-result` after the capture call returns.

At main revision `dc19de9204df9b58d6eaa5b0e4697e0657b617de`, moving the completion
marker or successful diagnostic result before the graph, or moving the graph
header after its records, still produced `candidate` for synthetic captures.
Appending orphan protocol/open/PCI/path rows after the footer could also leave
that result unchanged. Marker presence and uniqueness did not establish order.

The first framing patch also missed truncated outside rows (`open`, `opens`,
`handle`, `opens-status=broken`) and structural rows preceded by VT/NEL or other
Unicode line separators. Regression tests cover these refusal cases.

## Bounded fix and compatibility

The parser requires exact literal-newline-delimited frame markers in producer
order, and parses ownership records only within the header/completion frame.
Outside the frame, structural-token checks reject truncated or partial graph
rows and core probe rows, including cfg, mmio, pci-attributes, probe-target,
binding, img and prom. Broader line separators are used only for this outside
refusal check: they are never normalized into accepted frame markers.

Valid synthetic producer captures, ordinary preamble and trailing handoff logs,
ordinary Unicode transport prose, and a missing final newline remain accepted.
Optional `parent-baseline` observations retain their existing separate,
comparative-only contract: adding them cannot alter profile admission. This is
not a claim that every arbitrary probe field or internal record order is fully
validated.

## Safe validation

From the repository root:

```sh
python -B research/profile/test_graph_record_order.py
python -B -m unittest discover -s research/profile -p 'test_*.py'
git diff --check
```

The focused suite has 10 tests, including red reproductions, malformed outside
rows, control separators, and valid-format compatibility. The full profile
unittest discovery has 120 tests. Both suites pass on the reviewed patch;
`git diff --check` is clean. These commands use synthetic local files and do not
build or execute EFI, access hardware, run CUDA, or invoke PowerShell.

A separate temporary-copy integration check combined the PR #369 aggregate
fixture parser/tests with this `capture_graph.py` and ran
`python -I research/profile/test_aggregate_fixture_formats.py`: all 4 tests
passed. The temporary copy was removed afterward; no other worktree was changed.

## Limits

An ordered recorded footer cannot prove final persistence or flush success;
`internal-boot/boot/test_diagnostic.c` already documents that distinction.
The fix does not authenticate provenance, prove independent boots, or grant
hardware eligibility. `candidate` remains non-authorizing, with
`hardware_tested` and `write_eligible` false.
