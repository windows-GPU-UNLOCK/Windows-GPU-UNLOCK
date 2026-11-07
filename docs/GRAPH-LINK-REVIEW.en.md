# Existing graph relationship review

Use an existing graph-summary.json; no new capture, boot, settings change or installation.
The reader groups records by handle AND protocol. It exports display PCI identities and
GOP relationships only for a same-handle PCI/GOP or a PCI I/O BY_CHILD_CONTROLLER edge.
Edges under another protocol do not count. Unknown/ambiguous stays unresolved/ambiguous;
it is not evidence of absent hardware or proof of physical MUX routing. Handle pointers,
paths and arbitrary input text are not exported. Summary digest is copied as a claimed
capture identity, not recomputed against raw logs or hardware attestation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\research\profile\test-graph-links.ps1
```
Enter the existing summary path. Uses existing Python, no compiler/admin requirement.
Expected graph-links.json in a new Documents folder; -OutputRoot accepts an existing
writable local root. Return only that reviewed JSON if requested. Originals stay unchanged.
Stop on incomplete/unresolved/ambiguous/error; preserve files and report the result,
not another EFI run. All physical-routing/release/hardware/write flags remain false.

Local tests cover protocol isolation, missing child edge, ambiguity, duplicate handles,
incomplete captures, scope and size refusal. Supplied130 summary has unique IntelA7A8
PCI-I/O child link;173 remains unresolved under this deliberately narrow rule. Both
owners report direct Windows return separately. No Ada MMIO/unlock admission or new
resource capture is authorized by these observations.

## Device Path driver-child observation

A separate device_path_driver_child_status now reports an exact Device Path
BY_CHILD_CONTROLLER edge only when its nonzero agent matches the sole PCI-I/O
BY_DRIVER owner (self controller, count1); child count must also be1. Wrong agent,
duplicate owner, missing owner or wrong attributes/count remain unresolved.
This mirrors the relationship used in make-profile.py, not its full path/console/
image/resource qualification. The PCI-I/O-only status remains separate.
For173, that status stays unresolved while the new field is unique-agent-matched-link
to NVIDIA adapter0. No new capture or owner rerun is needed; this analysis used the
already supplied summary. Five local regressions and actual-summary runs passed.

## Unknown ROOT/SWD display identities

Preparation now treats every non-PCI display entry as requiring an explicit reviewed
identity, rather than silently excluding ROOT/SWD. The configuration schema still
forbids broad ROOT/SWD exceptions. Existing narrowly pinned signed LCI remains
unchanged; missing/duplicate/wrong driver metadata still refuses. A signed flag alone
does not turn ROOT/SWD into a known identity. Do not uninstall/disable an adapter or
change display/settings to pass. Keep preparation stopped pending source review.

The existing test-x99-graph-preparation.ps1 mock suite now covers ROOT, SWD, the
reported Punktfunk version with either signed state, and the prior LCI positive/
negative cases. It queries/stages no real device. This changes preflight refusal,
not firmware engine behavior, compatibility, ownership or unlock admission.
