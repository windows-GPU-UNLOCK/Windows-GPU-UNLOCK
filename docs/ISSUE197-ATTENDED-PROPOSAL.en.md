# Issue197: prepared graph boundary awaiting acceptance

The returned schema3 report records Secure Boot disabled, observed fully
decrypted volume/zero percent, exact2504/397D1462 and164E/7D751462 PCI devices.
These are reported Windows prerequisites, not preboot ownership or recovery
proof. No further inventory is needed before reviewing this proposal.

Exact preparation pins remain MSI MAG B650 TOMAHAWK WIFI (MS-7D75), BIOS1.R3,
7800X3D and both PCI adapters. Existing unknown-identity refusals remain.
The common script implements local Windows-ESP personalization, FAT32 USB
data-disk checks, loader backup/hash/readback, policy/encryption rechecks,
capture-preservation/no-repeat stops and summary collection. The actual ESP
GUID is obtained locally; no private partition identifier needs posting.

Proposed new hardware scope: one attended graph-only EFI run reading exposed
firmware handles/protocol/open relationships, GOP mode metadata, six console
variables and64-byte PCI headers on exposed PCI-I/O handles. It writes USB
logs, disables the EFI watchdog as the existing handoff does, and attempts
normal Windows Boot Manager return. No GPU MMIO/PROM/image dumps, detach,
reset, GPU writes/firmware execution, unlock or firmware-variable changes.

Firmware/display/input may hang; Windows may fail to start. An uncabled iGPU
is not proven fallback. Recovery is unproven: the proposed stop would be power
off/remove USB/use normal Windows Boot Manager if Windows has not started
within two minutes; stop if recovery fails. No automatic reboot/retry/rollback,
no setting/cable/FastStartup change and no reuse after an incomplete result.

Before any run instructions, the owner must explicitly accept this exact
scope/risks, e.g. reply ACCEPT-197-GRAPH. That is not unlock authorization.
Until then, keep EFI preparation/boot stopped. This document contains no
hardware execution command. The single optional CPU/file-only reproduction is:

```powershell
powershell -NoProfile -File .\research\profile\test-graph-offline.ps1 -Machine issue197 -PackagedFixture
```

Expected graph-build-test.json selecting issue197, configuration/mock staging
pass, FixtureOnly=true and hardware/write flags false; share only that JSON
if reproducing. Do not stage/boot the fixture. Stop on error; no installations
or settings changes. No repeat is needed to confirm maintainer validation.

Validation: newly compiled14848-byte AMD64 sample-GUID image, zero imports,
NX/dynamic-base, SHA7974eb71bfd46eec67672d31ee437d34b1da1c248082f7b0fc25179ff8765b52,
exact packaged-template byte equivalence; source/GUID/scope/hash/refusal tests,
all configuration fixtures, mock backup/readback/capture preservation, strict
policy gates,13 encryption cases and7 summary tests passed locally. The sample
GUID image is not the contributor's Windows-pinned build and must not be booted.
No physical USB was staged or EFI executed. Return evidence after a future
accepted run would be graph-summary.json plus direct/manual Windows outcome;
raw logs/EFI/backups remain local. Source and scope must be rechecked before
issuing that procedure if the case changes.
