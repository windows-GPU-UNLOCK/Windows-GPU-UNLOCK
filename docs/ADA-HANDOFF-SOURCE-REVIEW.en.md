# External Ada handoff changes: source review

Reviewed as source data on 2026-11-02; neither patch was built or executed.
Both external PRs remain open and unmerged at this review:

- [PR3](https://github.com/Zihao-Wu06/gpu-unlock-for-windows/pull/3),
  head698671bb3405fd38d4bea48fd4a7ea5e7b806847.
- [PR4](https://github.com/Zihao-Wu06/gpu-unlock-for-windows/pull/4),
  head724c4e806b688d3a95199f106c8d0c0732d034d7.

PR3 combines useful GOP diagnostics with firmware actions. Its target SetMode0
helper requires both framebuffer fields zero and a device-path parent matching
the target PCI handle. The separate ConnectController helper acts on enumerated
GOP handles and ConsoleOut, beyond that target-only ancestry check. These are
different action boundaries; accepting the diagnostic distinction does not
justify importing the entire reconnect sequence. Mode0 is not established as
the original display geometry or a universally usable recovery mode.

PR4's DisplayChildNoGop checks child attributes, agent, open count, bounded path
and target PCI ancestry. However, its live-framebuffer rejection only executes
when HandleProtocol succeeds with a non-null GOP, Mode and both framebuffer
fields nonzero. A lookup error, success with a null GOP, missing Mode or partial
framebuffer metadata can therefore proceed to the ancestry check. Ancestry
identifies a parent; it does not turn these unknown observations into evidence
that the display child is unused. The helper can return success after that
check, and its caller uses success to tolerate the unrecorded child.

Before any reuse here, the contract needs separate observable states for
protocol absence, lookup failure, malformed success, missing mode, partial/live
framebuffer, and positively observed zero framebuffer. Exact target ownership,
all child relationships, post-action revalidation and Windows return remain
separate prerequisites. This review does not add a fallback, release permission,
SetMode/reconnect call, profile, or hardware instructions.

The reported Inno3D4070Ti/Z690M hardware result in issue2 remains contributor
evidence. It does not qualify the original4070SUPER or the MSI4070Ti research
machine. The separate unpublished Windows-userland POC explicitly has no unlock
result and supplies no implementation to review; it is not this EFI patch.
