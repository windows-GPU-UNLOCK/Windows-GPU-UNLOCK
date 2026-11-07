# Issue17 Windows target separation

The PCI-parent reader selects 2204/40411458 and 1e04/12fa10de exactly once
each for case 17. It never traverses the non-target 2c02/41781458 device.
Missing or duplicate targets stop selection.

```powershell
powershell -NoProfile -File .\tools\test-pci-parents.ps1 -Case 17
```

The [returned v2 report](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/17#issuecomment-6571986594)
retained both PCI chains before later reads failed. Matching repeated
1022:43f5/43f4 models did not identify shared device instances; Pci:null tail
nodes did not mean absent ancestry. Its top-level observed status overstated
completion.

Version windows-pci-parent-v3 retains these boundaries and adds random IDs
shared across the two chains within one RunId. Equal NodeId values identify
the same reported Windows instance; equal vendor/device values alone do not.
Non-PCI nodes carry an allowlisted Kind. Complete requires both chains to
reach an explicit root; other retained results are partial with the exact
termination reason. Selection/inventory failure is error. The original
report cannot acquire missing IDs or root evidence retroactively.

Return only reviewed pci-parents.json from the printed Documents folder.
Raw device instance paths are omitted. No admin, Python, driver change,
PCI config/MMIO, EFI or reboot.
Keep all cards, cables and settings unchanged. If blocked/failing, stop and
send a short sanitized error; do not remove a card to make this test pass.

This inspects Windows associations toward a multi-target isolation review.
It does not prove physical slots, link width, firmware ownership, independent
release or unlock. TU102 1e04 is outside current generic probe admission;
vendor helper names do not grant family support. No GPU is admitted by this test.
See [the shared status contract](PCI-PARENT-TEST.en.md). CPU-only -SelfTest
covers same-model/different-instance bridges and an actual shared ancestor
using synthetic identities; it does not replay the contributor's raw topology.
