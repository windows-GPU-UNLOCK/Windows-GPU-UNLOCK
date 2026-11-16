# Issue38: independent receipt source provenance

On2026-11-02, independently compared all845 path/SHA256 entries in the
supplied Format2 host-test receipt with public Git blobs, without executing
contributor code or firmware. Every listed input matches exact bytes at
[d9094ae8b784cd8fecc529ab3cc21e6a52584f31](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/commit/d9094ae8b784cd8fecc529ab3cc21e6a52584f31).
No line-ending normalization was needed for these845 matches.

The receipt tree hash is
`654f2c97b8e5df0c5eac0c25ba5b059c1156684414de9acbb81812ca64f0898c`.
Against current main fd8bbea,842 match exactly; the three version differences
are research/pci-decode/snapshot.c, research/profile/proven.json and
research/profile/test_family_admission.py. They must not be labeled arbitrary
local changes merely because they differ from current main.

This establishes the public provenance of the receipt's listed source hashes.
It does not independently prove that those bytes were actually compiled/run
on the owner's host. The separately hashed generated header and private
PROM/driver/capture fixtures are not those845 tracked inputs; their actual
bytes were not reconstructed by this comparison. Owner-reported22 host jobs,
hardware unlock, direct Windows return and matched GEMM remain their own
evidence categories. No profile admission or new hardware run is authorized.

Maintainer review can now use the identified public source baseline while
retaining generated-header/fixture and transaction/cleanup evidence boundaries.
No additional contributor inventory, benchmark, EFI boot or repeat is requested.
