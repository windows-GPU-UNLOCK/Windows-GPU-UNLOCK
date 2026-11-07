# ZBOX existing Windows PCI associations (#167)

```powershell
powershell -NoProfile -File .\tools\test-pci-parents.ps1 -Case 167
```

Uses the shared Windows-only parent reader with exact 2504/263019da and
9bc8/b44019da data, returning the NVIDIA chain first, Intel chain second.
Mock tests verify RDP cannot substitute for the Intel PCI adapter; no RDP
parent lookup or ROOT/SWD exception is granted. This is not preboot topology,
a physical monitor/cable verification or an available recovery-path proof.
The EFI preparer's unknown-identity refusal remains unchanged. The same GPU
identity in another board profile does not transfer that board's qualification.

The [returned v2 report](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/167#issuecomment-6566566392)
records the NVIDIA target followed by Intel 8086:1901 and the separate Intel
9bc8 target. Both chains then reach non-PCI tail nodes before a read fails.
Those PCI observations remain useful; unavailable does not establish absent
parents or a firmware problem. Top-level observed did not mean either chain
completed.

Version windows-pci-parent-v3 labels non-PCI node kinds, correlates shared
Windows instances with random per-run NodeId values, and distinguishes an
exact root from failed reads, cycles and the depth limit. Expect complete
only if both chains complete, partial for retained incomplete chains, or error
for selection/inventory failure. Existing v2 data is not reclassified as
complete. See [the shared status contract](PCI-PARENT-TEST.en.md).
Return only reviewed pci-parents.json from the printed Documents folder.
No Python, administrator rights, firmware, PCI config/MMIO, driver changes,
settings changes, cable relocation, EFI or reboot. RDP may remain as it is.
If blocked/failing, stop and return a short sanitized error; do not remove
virtual adapters or reconnect the monitor to make the test pass.
