# Windows PCI parent associations (#108)

Run from extracted pinned source in normal Windows PowerShell:

```powershell
powershell -NoProfile -File .\tools\test-pci-parents.ps1
```

Reads present display inventory and DEVPKEY_Device_Parent only for the unique
2208/40811458 target, with at most 16 visited nodes including the target.
Version windows-pci-parent-v3 exports numeric PCI IDs/subsystems, hop order,
allowlisted non-PCI node kinds and random NodeId/ParentNodeId values. The same
Windows instance receives the same NodeId within one RunId; different instances
with the same bridge model receive different IDs. IDs cannot be compared across
runs. Raw instance paths, serials, names and error text are omitted.

Return only reviewed pci-parents.json from the printed Documents folder.
ReadStatus is complete only when every selected chain reaches the exact Windows
device-tree root or a successfully read empty parent. Otherwise it is partial
when nodes were retained, or error when selection/inventory failed. Each chain
records State, Termination and StopNodeId; parent-read-failed,
invalid-parent-response, cycle and depth-limit remain explicit partial results.
A returned parent beyond the depth limit can have a ParentNodeId without a
visited row. Failed reads never establish that a parent is absent.

Only the exact documented HTREE root terminates without a parent query.
An ordinary ROOT-enumerated device is still traversed; unknown non-PCI nodes
are retained as kind other. These are sequential Windows associations, not an
atomic snapshot, physical connector/slot proof, EFI ownership or unlock.
The [parent-property documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-parent)
defines the association; Microsoft's [root-node example](https://learn.microsoft.com/en-us/windows-hardware/drivers/debuggercmds/-devobj)
identifies the tree root separately from ROOT-enumerated devices.

Secure Boot, cards, cables and settings remain unchanged. No Python, elevation,
firmware dump, PCI config/MMIO access, driver change, EFI staging or reboot is
needed. Partial/error results are useful; do not change the machine to clear
them. If script policy blocks execution, return a short sanitized error.
All hardware/write/route-verification flags remain false.

Developer mock regression: add -SelfTest. This executes CPU-only synthetic
chains, including repeated bridge models, shared ancestors, non-PCI tails,
root/read-error/cycle/depth boundaries and aggregate status. It does not query
PnP, create report files or establish contributor hardware compatibility.
