# Offline capture parser review

Based on main `dc19de9204df9b58d6eaa5b0e4697e0657b617de`.

The device-path reader selected only syntactically valid hexadecimal rows.
A declared but malformed node could therefore disappear while the remaining
nodes still produced a positive single-RTX topology observation. The GOP
reader likewise used the first matching geometry row, ignoring a conflicting
second row or malformed suffix.

The reader now collects declared path-node and GOP framebuffer rows before
validating their complete syntax. Path nodes require lowercase, even-length
hexadecimal data. GOP geometry must occur exactly once and may use either the
legacy framebuffer/size pair or the producer's additional mode/max-mode pair.
LF and normalized CRLF are the only line boundaries for these checks, so
control characters cannot hide a malformed row suffix.

Valid device-path length/termination checks, nearest PCI parent selection,
pathless virtual-console observations and original-byte input hashes remain
unchanged. All hardware, detach, unlock and handoff authority flags remain
false. This corrects saved-evidence classification, not runtime admission.

## Offline tests

From the repository root, using Python 3:

```sh
python -m unittest discover -s research/headless -p 'test_*.py'
python -m unittest discover -s research/profile -p 'test_*.py'
python -m unittest discover -s tools -p 'test_*.py'
python -m unittest discover -s benchmark -p 'test*.py'
```

The headless suite passes 41 tests, profile 110, tools 14 and benchmark 28.
Synthetic regressions cover corrupt first/middle/final path rows on PCI and
GOP handles, empty/invalid/odd hexadecimal data, malformed termination,
conflicting or duplicate geometry in either order, both geometry formats,
nearest-parent selection, virtual consoles, LF/CRLF and nine non-LF control
separators. The baseline accepts the new malformed-path and duplicate-geometry
examples. Odd-length hexadecimal data was already rejected; its failure now
uses the same generic malformed-node message.

No real capture, PowerShell, firmware, EFI, GPU, USB, registry or hardware
operation was used. These checks do not authenticate capture freshness,
physical provenance or global graph completeness. Other existing CLI errors,
including filesystem errors, may still include local paths. Release manifests
were not refreshed; this is not a release or hardware approval.
